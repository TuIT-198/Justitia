CREATE TABLE hs_nomenclatures (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    edition_year smallint NOT NULL CHECK (edition_year BETWEEN 1988 AND 2200),
    issuing_body text NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUPERSEDED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE hs_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nomenclature_id uuid NOT NULL REFERENCES hs_nomenclatures(id) ON DELETE RESTRICT,
    code text NOT NULL,
    description_vi text,
    description_en text NOT NULL,
    level smallint NOT NULL CHECK (level BETWEEN 1 AND 12),
    parent_id uuid,
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (nomenclature_id, code),
    UNIQUE (nomenclature_id, id),
    FOREIGN KEY (nomenclature_id, parent_id)
        REFERENCES hs_codes(nomenclature_id, id) ON DELETE RESTRICT,
    CHECK (code ~ '^[0-9]+$')
);

CREATE TABLE product_hs_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    product_form_id uuid,
    market_id uuid NOT NULL REFERENCES markets(id) ON DELETE RESTRICT,
    nomenclature_id uuid NOT NULL,
    hs_code_id uuid NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (product_id, product_form_id)
        REFERENCES product_forms(product_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (nomenclature_id, hs_code_id)
        REFERENCES hs_codes(nomenclature_id, id) ON DELETE RESTRICT,
    UNIQUE (product_id, product_form_id, market_id, hs_code_id, valid_from),
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE INDEX idx_hs_codes_parent_id ON hs_codes(parent_id);
CREATE INDEX idx_product_hs_codes_lookup
    ON product_hs_codes(product_id, product_form_id, market_id, valid_from, valid_to);

