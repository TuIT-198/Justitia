CREATE TABLE export_batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    batch_code text NOT NULL,
    origin_country_id uuid NOT NULL REFERENCES countries(id) ON DELETE RESTRICT,
    destination_country_id uuid NOT NULL REFERENCES countries(id) ON DELETE RESTRICT,
    market_id uuid NOT NULL REFERENCES markets(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN (
            'DRAFT', 'PREPARING', 'READY_FOR_CHECK', 'UNDER_REVIEW',
            'ACTION_REQUIRED', 'READY_FOR_EXPORT', 'EXPORTED', 'CANCELLED'
        )),
    planned_export_date date,
    actual_export_date date,
    notes text,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (organization_id, batch_code),
    UNIQUE (organization_id, id),
    CHECK (batch_code = btrim(batch_code) AND length(batch_code) > 0),
    CHECK (deleted_at IS NULL OR deleted_at >= created_at)
);

CREATE TABLE export_batch_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variety_id uuid,
    product_form_id uuid NOT NULL,
    hs_code_id uuid REFERENCES hs_codes(id) ON DELETE RESTRICT,
    quantity numeric,
    quantity_unit text,
    net_weight_kg numeric,
    lot_reference text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (organization_id, batch_id)
        REFERENCES export_batches(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (product_id, variety_id)
        REFERENCES product_varieties(product_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (product_id, product_form_id)
        REFERENCES product_forms(product_id, id) ON DELETE RESTRICT,
    CHECK (quantity IS NULL OR quantity > 0),
    CHECK (quantity_unit IS NULL OR length(btrim(quantity_unit)) > 0),
    CHECK (net_weight_kg IS NULL OR net_weight_kg > 0),
    CHECK (lot_reference IS NULL OR length(btrim(lot_reference)) > 0)
);

CREATE INDEX idx_export_batches_organization_status
    ON export_batches(organization_id, status);
CREATE INDEX idx_export_batches_organization_planned_date
    ON export_batches(organization_id, planned_export_date);
CREATE INDEX idx_export_batch_items_organization_batch
    ON export_batch_items(organization_id, batch_id);
CREATE INDEX idx_export_batch_items_product_id
    ON export_batch_items(product_id);
CREATE INDEX idx_export_batch_items_hs_code_id
    ON export_batch_items(hs_code_id) WHERE hs_code_id IS NOT NULL;

