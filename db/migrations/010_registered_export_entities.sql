CREATE TABLE registered_export_entities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type text NOT NULL
        CHECK (entity_type IN (
            'GROWING_AREA', 'PACKING_FACILITY',
            'PROCESSING_FACILITY', 'STORAGE_FACILITY'
        )),
    registry_namespace citext NOT NULL,
    registry_code citext NOT NULL,
    name text NOT NULL,
    country_id uuid NOT NULL REFERENCES countries(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'REVOKED')),
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (registry_namespace, registry_code),
    CHECK (registry_namespace::text = btrim(registry_namespace::text)
        AND length(registry_namespace::text) > 0),
    CHECK (registry_code::text = btrim(registry_code::text)
        AND length(registry_code::text) > 0),
    CHECK (length(btrim(name)) > 0),
    CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object')
);

CREATE TABLE organization_registered_entities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    registered_entity_id uuid NOT NULL
        REFERENCES registered_export_entities(id) ON DELETE RESTRICT,
    relationship_type text NOT NULL
        CHECK (relationship_type IN ('OWNER', 'CONTRACTED', 'SUPPLIER', 'AUTHORIZED_USER')),
    valid_from date,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE batch_registered_entities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    registered_entity_id uuid NOT NULL
        REFERENCES registered_export_entities(id) ON DELETE RESTRICT,
    entity_role text NOT NULL
        CHECK (entity_role IN ('GROWER', 'PACKER', 'PROCESSOR', 'STORAGE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (organization_id, batch_id)
        REFERENCES export_batches(organization_id, id) ON DELETE CASCADE,
    UNIQUE (organization_id, batch_id, registered_entity_id, entity_role)
);

CREATE INDEX idx_registered_entities_country_type
    ON registered_export_entities(country_id, entity_type);
CREATE INDEX idx_organization_registered_entities_lookup
    ON organization_registered_entities(organization_id, registered_entity_id);
CREATE INDEX idx_batch_registered_entities_registered_entity
    ON batch_registered_entities(registered_entity_id);
