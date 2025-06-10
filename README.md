# Projeto Webhook
Autor: Leonardo Scarlato

## Introdução
Webhook é um mecanismo de comunicação entre sistemas que permite que um servidor notifique outro automaticamente quando um determinado evento ocorre, sem que o segundo precise perguntar continuamente (evitando polling).

Tecnicamente, Webhook é uma chamada HTTP feita por um sistema para um endpoint previamente configurado em outro sistema, disparada por um evento específico.

Características principais:
- Baseado em eventos (event-driven)
- Comunicação assíncrona
- Usa requisições HTTP (geralmente POST)
- O sistema receptor deve estar pronto para receber e processar a requisição

## Como funciona normalmente?
1. O Cliente faz uma requisição para iniciar um processo (ex: pagamento) e é redirecionado para a página do Gateway de Pagamento.
2. O Cliente realiza o pagamento normalmente na forma como desejar (PIX, cartão, etc.)
3. Após o pagamento, o site redireciona de volta para a página da loja.
4. Ao mesmo tempo, o Gateway envia uma requisição no Webhook informando do evento de pagamento.
5. O webhook é encarregado de confirmar e registrar o pagamento.
6. O front então é atualizado com o resultado do processamento do Webhook.

## Descrição do Projeto
Este projeto é um exemplo de implementação de Webhook utilizando programação funcional por meio da linguagem OCaml, com o objetivo de simular um sistema de verificação de transações de pagamento, registrando tais eventos em um banco de dados.

## Estrutura do Projeto
```
projeto-webhook-progfunc/
├── test/
    ├── payloads/
        ├── payload_correto.json            # Exemplo de payload válido
        ├── payload_campo_faltante.json     # Exemplo de payload com campo faltante
        └── payload_amount_invalido.json    # Exemplo de payload com campo inválido
    ├── test_webhook.py                     # Script de testes para o Webhook
├── webhook/
    ├── bin/
        ├── main.ml       # Código principal do servidor webhook
        ├── db.ml         # Camada de persistência em SQLite
        └── dune
    ├── lib/
        └── dune          # Definição da biblioteca
    ├── webhook.db        # Banco SQLite gerado quando o projeto é executado
    └── dune-project      # Configuração do projeto Dune
├── README.md          # Documentação do projeto
├── .gitignore         # Arquivo para ignorar arquivos no Git
```

## Technologias Utilizadas
- **OCaml**: Linguagem de programação funcional utilizada para implementar o Webhook.
    - Uso das bibliotecas `Cohttp` e `Lwt` para construção do servidor HTTP assíncrono.
    - `Yojson` para manipulação de JSON.
    - `Sqlite3`: Banco de dados leve utilizado para persistência dos dados do Webhook.

- **Dune**: Sistema de build para projetos OCaml.
- **Python**: Utilizado para os testes do Webhook, simulando requisições HTTP e verificando as respostas.

## Como Executar o Projeto

1. **Clonar o repositório**:
   Primeiro, clone o repositório do projeto para sua máquina local:
    ```bash
    git clone https://github.com/leoscarlato/projeto-webhook-progfunc
    cd projeto-webhook-progfunc
    ```
2. **Instalar as dependências**:
    Certifique-se de ter o OCaml e o Dune instalados. Você pode instalar as dependências do projeto com:
     ```bash
     opam install cohttp-lwt-unix lwt yojson sqlite3
     ```
3. **Compilar o projeto**:
    Dentro do diretório do projeto e compile com Dune:
    ```bash
    dune build
    ```
4. **Executar o servidor Webhook**:
    Após a compilação, você pode executar o servidor Webhook com:
    ```bash
    dune exec webhook
    ```
5. **Testar o Webhook**:
    É possível testar o Webhook de duas formas:
    - **Usando o script de testes**:
      Execute o script de testes em Python para verificar se o Webhook está funcionando corretamente:
      ```bash
      python3 test/test_webhook.py
      ```

    Neste caso, a resposta esperada é de que todos os testes passem, indicando que o Webhook está funcionando conforme o esperado. A resposta esperada quando o script é executado com sucesso é:
    ```
    ✅ Confirmação recebida: {'event': 'payment_success', 'transaction_id': 'abc123', 'amount': '49.90', 'currency': 'BRL', 'timestamp': '2023-10-01T12:00:00Z'}
    1. Webhook test ok: successful!
    2. Webhook test ok: transação duplicada!
    ❌ Cancelamento recebido: {'event': 'payment_success', 'transaction_id': 'abc123a', 'amount': '0.00', 'currency': 'BRL', 'timestamp': '2023-10-01T12:00:00Z'}
    3. Webhook test ok: amount incorreto!
    4. Webhook test ok: Token Invalido!
    5. Webhook test ok: Payload Invalido!
    ❌ Cancelamento recebido: {'event': 'payment_success', 'transaction_id': 'abc123abc', 'amount': '0.00', 'currency': 'BRL'}
    6. Webhook test ok: Campos ausentes!
    6/6 tests completed.
    Confirmações recebidas: ['abc123']
    Cancelamentos recebidos: ['abc123a', 'abc123abc']
    ```

    ⚠️ **Importante**: para que os testes funcionem corretamente, o servidor Webhook deve estar rodando em segundo plano, isto é, devem ser usados dois terminais: um para executar o servidor e outro para rodar os testes.

    - **Usando ferramentas como Postman ou cURL**:
        É possível enviar requisições HTTP em duas rotas diferentes:
        - `POST /webhook`: Para enviar um payload de transação.
        - `GET /`: Para verificar o status do Webhook.
6. **Verificar o banco de dados**:
    O banco de dados SQLite será criado automaticamente na primeira execução do servidor. Ele estará localizado no diretório `webhook/` para visualização e verificação dos dados persistidos.

## Funcionalidades Implementadas
- Verificação de integridade do payload recebido.
- Registro de transações no banco de dados SQLite.
- Respostas adequadas para diferentes cenários de payload (válido, inválido, campos faltantes).
- Cancelamento de transações em caso de divergências
- Confirmação de transações em caso de sucesso.

## ⚠️ Importante
Para este projeto, foram utilizadas ferramentas de Inteligência Artificial (IA) com os seguintes propósitos:
- Auxílio na geração de código OCaml.
- Descrições das funções utilizadas.
- Correção de erros e sugestões de melhorias.


