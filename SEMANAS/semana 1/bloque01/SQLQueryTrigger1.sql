
CREATE TRIGGER dbo.trg_caso_aud ON dbo.caso
AFTER INSERT, UPDATE, DELETE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @i INT = (SELECT COUNT(*) FROM inserted), @d INT = (SELECT COUNT(*) FROM deleted);
  IF @i = 0 AND @d = 0 RETURN;
  INSERT dbo.log_auditoria(objeto, operacion, detalle, estado)
  VALUES ('dbo.caso',
          CASE WHEN @i > 0 AND @d > 0 THEN 'UPDATE' WHEN @i > 0 THEN 'INSERT' ELSE 'DELETE' END,
          CONCAT('filas=', CASE WHEN @i > 0 THEN @i ELSE @d END), 'OK');
END;
GO