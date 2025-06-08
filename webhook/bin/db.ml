open Sqlite3

(* Abre (ou cria) o arquivo de banco e inicializa a tabela *)
let db =
  let handle = db_open "webhook.db" in
  let sql =
    "CREATE TABLE IF NOT EXISTS transactions (" ^
    "transaction_id TEXT PRIMARY KEY, " ^
    "event TEXT, " ^
    "amount REAL, " ^
    "currency TEXT, " ^
    "timestamp TEXT, " ^
    "status TEXT)"
  in
  ignore (exec handle sql);
  handle

(* Persistência de transações *)
let persist_txn ~id ~event ~amount ~currency ~timestamp ~status =
  let stmt =
    prepare db
      "INSERT OR REPLACE INTO transactions \
       (transaction_id,event,amount,currency,timestamp,status) \
       VALUES (?, ?, ?, ?, ?, ?)"
  in
  bind stmt 1 (Data.TEXT id)    |> ignore;
  bind stmt 2 (Data.TEXT event) |> ignore;
  bind stmt 3 (Data.FLOAT amount) |> ignore;
  bind stmt 4 (Data.TEXT currency) |> ignore;
  bind stmt 5 (Data.TEXT timestamp) |> ignore;
  bind stmt 6 (Data.TEXT status)   |> ignore;
  ignore (step stmt);
  finalize stmt