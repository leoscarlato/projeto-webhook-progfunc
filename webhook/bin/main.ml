open Lwt.Infix
open Cohttp
open Cohttp_lwt_unix

(* Define o token que consideramos "válido". Pode ser sobrescrito pela variável de
   ambiente WEBHOOK_TOKEN, ou ficará “meu-token-secreto” por padrão. *)
let expected_token =
  match Sys.getenv_opt "WEBHOOK_TOKEN" with
  | Some t -> t
  | None   -> "meu-token-secreto"

(* Esta função tenta extrair o campo "transaction_id" como string, mesmo que os
   outros campos (event, amount etc.) estejam faltando ou estejam com tipo errado.
   Se transaction_id não existir ou não for string, retorna "" (string vazia). *)
let extract_txn_id (json : Yojson.Safe.t) : string =
  let open Yojson.Safe.Util in
  try json |> member "transaction_id" |> to_string
  with _ -> ""

(*Extrair campo "event" como string. Se não existir, ou não for string, devolve None. *)
let extract_event (json : Yojson.Safe.t) : string option =
  let open Yojson.Safe.Util in
  try Some (json |> member "event" |> to_string)
  with _ -> None

(*Extrair "amount", aceitando número ou string que possa converter *)
let extract_amount (json : Yojson.Safe.t) : float option =
  let open Yojson.Safe.Util in
  try
    match json |> member "amount" with
    | `String s   -> Some (float_of_string s)
    | `Float f    -> Some f
    | `Int   i    -> Some (float_of_int i)
    | _           -> None
  with
  | Failure _ -> None
  | _ -> None

(*Extrair "currency" como string, se existir *)
let extract_currency (json : Yojson.Safe.t) : string option =
  let open Yojson.Safe.Util in
  try Some (json |> member "currency" |> to_string)
  with _ -> None

(*Extrair "timestamp" como string, se existir *)
let extract_timestamp (json : Yojson.Safe.t) : string option =
  let open Yojson.Safe.Util in
  try Some (json |> member "timestamp" |> to_string)
  with _ -> None

let seen_transactions : (string, unit) Hashtbl.t = Hashtbl.create 1024

(* Retorna false se txn_id já existe; caso contrário registra e devolve true *)
let check_and_register_txn_id (txn_id : string) : bool =
  if Hashtbl.mem seen_transactions txn_id then false
  else (
    Hashtbl.add seen_transactions txn_id ();
    true
  )

let json_of_whole_payload (json : Yojson.Safe.t) : Yojson.Safe.t =
  (* Devolve o mesmo JSON recebido*)
  json

let confirmation_url = "http://127.0.0.1:5001/confirmar"
let cancellation_url = "http://127.0.0.1:5001/cancelar"

let post_to_url ~(url:string) ~(body_json:Yojson.Safe.t) : unit Lwt.t =
  let headers = Header.init_with "Content-Type" "application/json" in
  let body_str = Yojson.Safe.to_string body_json in
  let body = Cohttp_lwt.Body.of_string body_str in
  Client.post ~headers ~body (Uri.of_string url) >>= fun (_resp, _resp_body) ->
  Lwt.return_unit

let callback _conn (req : Request.t) (body : Cohttp_lwt.Body.t)
  : (Response.t * Cohttp_lwt.Body.t) Lwt.t =
  let uri  = Request.uri req in
  let path = Uri.path uri in
  let meth = Request.meth req in

  (* Só atendemos POST em /webhook *)
  if not (meth = `POST && path = "/webhook") then
    let resp = Response.make ~status:`Not_found () in
    Lwt.return (resp, Cohttp_lwt.Body.of_string "404: Not Found")
  else
    (* 7.1. Verifica cabeçalho “X-Webhook-Token” *)
    let headers = Request.headers req in
    let token_opt = Header.get headers "x-webhook-token" in
    match token_opt with
    | None ->
        (* Sem cabeçalho => 401 Unauthorized *)
        let resp = Response.make ~status:`Unauthorized () in
        Lwt.return (resp, Cohttp_lwt.Body.of_string "Missing token")
    | Some token_value ->
        if token_value <> expected_token then
          (* Token inválido => 401 Unauthorized *)
          let resp = Response.make ~status:`Unauthorized () in
          Lwt.return (resp, Cohttp_lwt.Body.of_string "Invalid token")
        else
          (* 7.2. Lê corpo inteiro como string *)
          Cohttp_lwt.Body.to_string body >>= fun body_str ->
          (* Se body for vazio (JSON “{}” ou string vazia), falha direto *)
          let json_parsed =
            try Ok (Yojson.Safe.from_string body_str)
            with Yojson.Json_error _ -> Error "Malformed JSON"
          in
          match json_parsed with
          | Error _ ->
              (* Payload não é JSON válido => 400 Bad Request *)
              let resp = Response.make ~status:`Conflict () in
              Lwt.return (resp, Cohttp_lwt.Body.of_string "Invalid JSON")

          | Ok json_obj ->
              (* Extrai transaction_id mesmo que faltem outros campos *)
              let txn_id = extract_txn_id json_obj in
              if String.trim txn_id = "" then
                (* Sem transaction_id: 400 Bad Request (não há como confirmar/cancelar) *)
                let resp = Response.make ~status:`Conflict () in
                Lwt.return (resp, Cohttp_lwt.Body.of_string "Missing transaction_id")
              else
                (* Agora temos um transaction_id não vazio. Podemos verificar duplicata. *)
                if not (check_and_register_txn_id txn_id) then
                  (* 2º POST com mesmo txn_id deve falhar (código ≠ 200). *)
                  let resp = Response.make ~status:`Conflict () in
                  Lwt.return (resp, Cohttp_lwt.Body.of_string "Duplicate transaction_id")
                else
                  (* transaction_id novo, token válido, JSON bem formado. 
                     Agora precisamos extrair e validar os demais campos. *)

                  (* 7.3. Extrair event, amount, currency, timestamp *)
                  let event_opt     = extract_event json_obj in
                  let amount_opt    = extract_amount json_obj in
                  let currency_opt  = extract_currency json_obj in
                  let timestamp_opt = extract_timestamp json_obj in

                  (* Se faltar qualquer um desses, chamamos /cancelar e retornamos ≠ 200 *)
                  match (event_opt, amount_opt, currency_opt, timestamp_opt) with
                  | (Some event, Some amount, Some _currency, Some _timestamp) ->
                      (* Todos os campos existem em algum formato *)
                      if event <> "payment_success" then
                        (* Evento “payment_failed” ou outro => cancelar *)
                        let () = Lwt.async (fun () ->
                          post_to_url ~url:cancellation_url ~body_json:(json_of_whole_payload json_obj)
                        ) in
                        let resp = Response.make ~status:`Conflict () in
                        Lwt.return (resp, Cohttp_lwt.Body.of_string "Invalid event")

                      else if amount <= 0.0 then
                        (* amount = 0 ou negativo => cancelar *)
                        let () = Lwt.async (fun () ->
                          post_to_url ~url:cancellation_url ~body_json:(json_of_whole_payload json_obj)
                        ) in
                        let resp = Response.make ~status:`Conflict () in
                        Lwt.return (resp, Cohttp_lwt.Body.of_string "Invalid amount")

                      else
                        (* Tudo ok => confirmar *)
                        let () = Lwt.async (fun () ->
                          post_to_url ~url:confirmation_url ~body_json:(json_of_whole_payload json_obj)
                        ) in
                        let resp = Response.make ~status:`OK () in
                        Lwt.return (resp, Cohttp_lwt.Body.of_string "OK")

                  | _ ->
                      (* Algum campo faltando (event ou amount ou currency ou timestamp) => cancelar *)
                      let () = Lwt.async (fun () ->
                        post_to_url ~url:cancellation_url ~body_json:(json_of_whole_payload json_obj)
                      ) in
                      let resp = Response.make ~status:`Conflict () in
                      Lwt.return (resp, Cohttp_lwt.Body.of_string "Missing fields")
;;

let port = 5000

let () =
  let mode   = `TCP (`Port port) in
  let config = Server.make ~callback () in
  Printf.printf "Servidor OCaml rodando em http://0.0.0.0:%d/webhook\n%!" port;
  Lwt_main.run (Server.create ~mode config)
