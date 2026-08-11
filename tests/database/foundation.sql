BEGIN;

DO $$
DECLARE
    user_one uuid;
    user_two uuid;
    org_one uuid;
    member_one uuid;
    product_one uuid;
    nomenclature_one uuid;
    nomenclature_two uuid;
BEGIN
    INSERT INTO users(email, full_name, status)
    VALUES ('foundation@example.com', 'Foundation One', 'ACTIVE') RETURNING id INTO user_one;

    IF EXISTS (SELECT 1 FROM user_credentials WHERE user_id = user_one) THEN
        RAISE EXCEPTION 'A user unexpectedly requires a local credential';
    END IF;

    BEGIN
        INSERT INTO users(email, full_name) VALUES ('FOUNDATION@EXAMPLE.COM', 'Duplicate');
        RAISE EXCEPTION 'Case-insensitive duplicate email was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO users(email, full_name, status)
    VALUES ('member-two@example.com', 'Foundation Two', 'ACTIVE') RETURNING id INTO user_two;
    INSERT INTO organizations(name, created_by)
    VALUES ('Foundation Test Organization', user_one) RETURNING id INTO org_one;
    INSERT INTO organization_members(organization_id, user_id, status, joined_at)
    VALUES (org_one, user_two, 'ACTIVE', now()) RETURNING id INTO member_one;

    INSERT INTO organization_member_roles(organization_id, organization_member_id, role_id)
    SELECT org_one, member_one, id FROM roles WHERE code IN ('MANAGER', 'COMPLIANCE');
    IF (SELECT count(*) FROM organization_member_roles WHERE organization_member_id = member_one) <> 2 THEN
        RAISE EXCEPTION 'A member could not receive multiple roles';
    END IF;

    BEGIN
        INSERT INTO organization_members(organization_id, user_id) VALUES (org_one, user_two);
        RAISE EXCEPTION 'Duplicate organization member was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO products(code, name_vi, name_en, category)
    VALUES ('FOUNDATION_TEST', 'Kiểm thử', 'Foundation test', 'TEST') RETURNING id INTO product_one;
    INSERT INTO product_forms(product_id, code, name_vi, name_en)
    VALUES (product_one, 'FRESH', 'Tươi', 'Fresh');
    BEGIN
        INSERT INTO product_forms(product_id, code, name_vi, name_en)
        VALUES (product_one, 'FRESH', 'Tươi lần hai', 'Fresh duplicate');
        RAISE EXCEPTION 'Duplicate product form code was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO hs_nomenclatures(code, name, edition_year, issuing_body, valid_from)
    VALUES ('TEST_A', 'Test A', 2022, 'Test', DATE '2022-01-01') RETURNING id INTO nomenclature_one;
    INSERT INTO hs_nomenclatures(code, name, edition_year, issuing_body, valid_from)
    VALUES ('TEST_B', 'Test B', 2022, 'Test', DATE '2022-01-01') RETURNING id INTO nomenclature_two;
    INSERT INTO hs_codes(nomenclature_id, code, description_en, level)
    VALUES
        (nomenclature_one, '0801', 'Test code A', 4),
        (nomenclature_two, '0801', 'Test code B', 4);
END $$;

ROLLBACK;

SELECT 'foundation database assertions passed' AS result;

