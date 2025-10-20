

DROP TABLE IF EXISTS itens_pedido CASCADE;
DROP TABLE IF EXISTS pedidos CASCADE;
DROP TABLE IF EXISTS produtos CASCADE;

CREATE TABLE produtos (
    produto_id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    preco NUMERIC(10,2) NOT NULL CHECK (preco >= 0),
    quantidade_em_estoque INT NOT NULL CHECK (quantidade_em_estoque >= 0)
);

CREATE TABLE pedidos (
    pedido_id SERIAL PRIMARY KEY,
    data_pedido TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status VARCHAR(20) NOT NULL DEFAULT 'processando'
        CHECK (status IN ('processando','concluido','cancelado'))
);

CREATE TABLE itens_pedido (
    item_id SERIAL PRIMARY KEY,
    pedido_id INT NOT NULL REFERENCES pedidos (pedido_id) ON DELETE CASCADE,
    produto_id INT NOT NULL REFERENCES produtos (produto_id),
    quantidade INT NOT NULL CHECK (quantidade > 0),
    preco_unitario NUMERIC(10,2) NOT NULL CHECK (preco_unitario >= 0)
);

CREATE INDEX idx_itens_pedido_pedido ON itens_pedido(pedido_id);
CREATE INDEX idx_itens_pedido_produto ON itens_pedido(produto_id);


INSERT INTO produtos (nome, preco, quantidade_em_estoque) VALUES
('Mouse Gamer RGB',      150.00, 20),
('Teclado Mecânico',     350.50, 15),
('Headset 7.1 Surround', 499.99, 10),
('Monitor 144Hz',       1200.00,  5);


CREATE OR REPLACE FUNCTION processar_venda(p_produto_id INT, p_quantidade INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_estoque   INT;
    v_preco     NUMERIC(10,2);
    v_pedido_id INT;
BEGIN
    IF p_quantidade <= 0 THEN
        RAISE EXCEPTION 'Quantidade inválida: %', p_quantidade;
    END IF;

    
    SELECT quantidade_em_estoque, preco
      INTO v_estoque, v_preco
      FROM produtos
     WHERE produto_id = p_produto_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Produto % não encontrado', p_produto_id;
    END IF;

    IF v_estoque < p_quantidade THEN
        RAISE EXCEPTION 'Estoque insuficiente (disp=%, solic=%)', v_estoque, p_quantidade;
    END IF;

    
    INSERT INTO pedidos (status) VALUES ('processando') --Essa linha cria um novo pedido com status 'processando'
      RETURNING pedido_id INTO v_pedido_id; --e guarda o ID gerado (campo pedido_id) dentro da variável v_pedido_id pra ser usado nas próximas etapas da venda.


    
    INSERT INTO itens_pedido (pedido_id, produto_id, quantidade, preco_unitario) --Essa linha grava o produto dentro do pedido, dizendo: “No pedido X, foi vendido o produto Y, na quantidade Z, com preço tal”.
    VALUES (v_pedido_id, p_produto_id, p_quantidade, v_preco);

    
    UPDATE produtos
       SET quantidade_em_estoque = quantidade_em_estoque - p_quantidade ---- Atualiza o estoque: subtrai a quantidade vendida do produto correspondente.
     WHERE produto_id = p_produto_id;

    
    UPDATE pedidos SET status = 'concluido' WHERE pedido_id = v_pedido_id; ---- Atualiza o status apenas do pedido recém-criado (identificado por v_pedido_id).

    RETURN v_pedido_id; 

EXCEPTION
    WHEN OTHERS THEN
        IF v_pedido_id IS NOT NULL THEN
            UPDATE pedidos SET status = 'cancelado' WHERE pedido_id = v_pedido_id;
 
        END IF;
        RAISE;
END;
$$;


CREATE OR REPLACE VIEW v_pedido_resumo AS
SELECT
  p.pedido_id,
  p.data_pedido,
  p.status,
  COALESCE(SUM(i.quantidade * i.preco_unitario),0) AS total
FROM pedidos p
LEFT JOIN itens_pedido i ON i.pedido_id = p.pedido_id
GROUP BY p.pedido_id, p.data_pedido, p.status; --Soma todos os itens de cada pedido e devolve um resumo por pedido (um por linha).



BEGIN;
SELECT processar_venda(1, 2);
COMMIT;


BEGIN;
SELECT processar_venda(4, 10);
ROLLBACK;


SELECT * FROM produtos ORDER BY produto_id; --Mostra o estoque atual de cada produto (depois da primeira venda)
SELECT * FROM pedidos ORDER BY pedido_id; -- Mostra todos os pedidos existentes (o da 1ª transação aparece, o da 2ª não).
SELECT * FROM itens_pedido ORDER BY item_id; --Mostra todos os pedidos existentes (o da 1ª transação aparece, o da 2ª não).
SELECT * FROM v_pedido_resumo ORDER BY pedido_id DESC LIMIT 10; --Mostra um resumo dos pedidos (id, data, status, total) — limitado aos 10 últimos.
 