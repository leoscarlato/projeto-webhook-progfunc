# projeto_webhook

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
