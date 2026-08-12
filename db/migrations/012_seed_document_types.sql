INSERT INTO document_types (
    code, name_vi, name_en, requires_ocr, requires_verification, is_active
) VALUES
    ('PHYTOSANITARY_CERTIFICATE', 'Giấy chứng nhận kiểm dịch thực vật', 'Phytosanitary Certificate', true, true, true),
    ('LAB_REPORT', 'Phiếu kết quả kiểm nghiệm', 'Laboratory Report', true, true, true),
    ('PUC_REGISTRATION', 'Đăng ký mã số vùng trồng', 'Growing Area Registration', true, true, true),
    ('PHC_REGISTRATION', 'Đăng ký cơ sở đóng gói', 'Packing Facility Registration', true, true, true)
ON CONFLICT (code) DO UPDATE SET
    name_vi = EXCLUDED.name_vi,
    name_en = EXCLUDED.name_en,
    requires_ocr = EXCLUDED.requires_ocr,
    requires_verification = EXCLUDED.requires_verification,
    is_active = EXCLUDED.is_active,
    updated_at = now();

