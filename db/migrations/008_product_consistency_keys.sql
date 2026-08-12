ALTER TABLE product_varieties
    ADD CONSTRAINT uq_product_varieties_product_id_id UNIQUE (product_id, id);

