CREATE OR ALTER PROCEDURE dbo.usp_validar
AS
BEGIN
  SET NOCOUNT ON;
  BEGIN TRY
    DECLARE @malas INT;
    SELECT @malas = COUNT(*) FROM (
      SELECT ano, semana, edad FROM stg.zoonosis_raw
      UNION ALL SELECT ano, semana, edad FROM stg.dengue_raw) t
    WHERE TRY_CAST(ano AS INT) NOT BETWEEN 2000 AND YEAR(GETDATE()) OR TRY_CAST(ano AS INT) IS NULL
       OR TRY_CAST(semana AS INT) NOT BETWEEN 1 AND 53 OR TRY_CAST(semana AS INT) IS NULL
       OR TRY_CAST(NULLIF(edad,'') AS INT) NOT BETWEEN 0 AND 120;
    INSERT dbo.log_auditoria(objeto, operacion, detalle, estado)
    VALUES ('usp_validar', 'VALIDAR', CONCAT('Filas invalidas: ', @malas), 'OK');
  END TRY
  BEGIN CATCH
    INSERT dbo.log_auditoria(objeto, operacion, detalle, estado)
    VALUES ('usp_validar', 'VALIDAR', ERROR_MESSAGE(), 'ERROR');
    THROW;
  END CATCH
END;
GO
