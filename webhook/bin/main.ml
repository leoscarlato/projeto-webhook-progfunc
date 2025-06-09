open Lwt.Infix
open Cohttp
open Cohttp_lwt_unix
open Yojson.Safe
open Yojson.Safe.Util
open Db

(* Token de segurança (X-Webhook-Token) *)
let expected_token =
  Sys.getenv_opt "WEBHOOK_TOKEN"
  |> Option.value ~default:"meu-token-secreto"

let confirmation_url = "http://127.0.0.1:5001/confirmar"
let cancellation_url  = "http://127.0.0.1:5001/cancelar"

(* Extração de campos do JSON *)
let extract_txn_id json    = try json |> member "transaction_id" |> to_string    with _ -> ""
let extract_event  json    = try Some (json |> member "event"         |> to_string) with _ -> None
let extract_amount json    =
  try match json |> member "amount" with
      | `String s -> Some (float_of_string s)
      | `Float f  -> Some f
      | `Int i    -> Some (float_of_int i)
      | _         -> None
  with _ -> None
let extract_currency json  = try Some (json |> member "currency"      |> to_string) with _ -> None
let extract_timestamp json = try Some (json |> member "timestamp"     |> to_string) with _ -> None

(* Controle de duplicatas em memória *)
let seen_txns = Hashtbl.create 1024
let is_new_txn id =
  if Hashtbl.mem seen_txns id then false
  else (
    Hashtbl.add seen_txns id ();
    true
  )

(* Helper para resposta de cancelamento *)
let respond_cancel json msg : (Response.t * Cohttp_lwt.Body.t) Lwt.t =
  let id    = extract_txn_id    json in
  let ev    = extract_event     json |> Option.value ~default:"" in
  let amt   = extract_amount    json |> Option.value ~default:0.0 in
  let cur   = extract_currency  json |> Option.value ~default:"" in
  let ts    = extract_timestamp json |> Option.value ~default:"" in
  (* Persiste como "cancelled" no DB *)
  ignore (persist_txn ~id ~event:ev ~amount:amt ~currency:cur ~timestamp:ts ~status:"cancelled");
  (* Dispara cancelamento via webhook async *)
  Lwt.async (fun () ->
    let headers = Header.init_with "Content-Type" "application/json" in
    let body    = Yojson.Safe.to_string json |> Cohttp_lwt.Body.of_string in
    Client.post ~headers ~body (Uri.of_string cancellation_url) >|= fun _ -> ()
  );
  (* Retorna 409 Conflict *)
  Server.respond_string ~status:`Conflict ~body:msg ()

(* Helper para resposta de confirmação *)
let respond_confirm json : (Response.t * Cohttp_lwt.Body.t) Lwt.t =
  let id    = extract_txn_id    json in
  let ev    = extract_event     json |> Option.value ~default:"" in
  let amt   = extract_amount    json |> Option.value ~default:0.0 in
  let cur   = extract_currency  json |> Option.value ~default:"" in
  let ts    = extract_timestamp json |> Option.value ~default:"" in
  (* Persiste como "confirmed" no DB *)
  ignore (persist_txn ~id ~event:ev ~amount:amt ~currency:cur ~timestamp:ts ~status:"confirmed");
  (* Dispara confirmação via webhook async *)
  Lwt.async (fun () ->
    let headers = Header.init_with "Content-Type" "application/json" in
    let body    = Yojson.Safe.to_string json |> Cohttp_lwt.Body.of_string in
    Client.post ~headers ~body (Uri.of_string confirmation_url) >|= fun _ -> ()
  );
  (* Retorna 200 OK *)
  Server.respond_string ~status:`OK ~body:"OK" ()

(* Callback principal *)
let callback _conn (req:Request.t) (body:Cohttp_lwt.Body.t)
  : (Response.t * Cohttp_lwt.Body.t) Lwt.t =
  match Request.meth req, Uri.path (Request.uri req) with
  | `POST, "/webhook" ->
    (* Valida token *)
    begin match Header.get (Request.headers req) "x-webhook-token" with
    | None | Some "" ->
      Server.respond_string ~status:`Unauthorized ~body:"Missing token" ()
    | Some t when t <> expected_token ->
      Server.respond_string ~status:`Unauthorized ~body:"Invalid token" ()
    | Some _ ->
      (*Lê corpo e parseia JSON*)
      Cohttp_lwt.Body.to_string body >>= fun s ->
      begin match
        try Ok (from_string s) with Yojson.Json_error _ -> Error ()
      with
      | Error _ ->
        Server.respond_string ~status:`Bad_request ~body:"Invalid JSON" ()
      | Ok json ->
        (*Extrai txn_id*)
        let txn_id = extract_txn_id json in

        (* Se missing id ou duplicata, trata sem chamar webhook adicional *)
        if txn_id = "" then
          respond_cancel json "Missing transaction_id"
        else if not (is_new_txn txn_id) then
          Server.respond_string ~status:`Conflict ~body:"Duplicate transaction" ()
        else
          (* transaction_id novo: checa event/amount/timestamp *)
          begin match extract_event json, extract_amount json, extract_timestamp json with
          | Some "payment_success", Some a, Some _ when a > 0.0 ->
            respond_confirm json
          | Some _, Some a, _ when a <= 0.0 ->
            respond_cancel json "Invalid amount"
          | _ ->
            respond_cancel json "Missing or invalid fields"
          end
      end
    end

  | `GET, "/" ->
    Server.respond_string ~status:`OK ~body:"Servidor OCaml no ar!" ()
  | _ ->
    Server.respond_string ~status:`Not_found ~body:"404: Not Found" ()

let () =
  let port = 5000 in
  Printf.printf "Servidor rodando em http://0.0.0.0:%d\n%!" port;
  Lwt_main.run (
    Server.create
      ~mode:(`TCP (`Port port))
      (Server.make ~callback ())
  )