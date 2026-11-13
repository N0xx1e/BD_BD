CREATE PROCEDURE dbo.usp_cargar
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @fase INT = 1, @n1 INT, @n2 INT;
  BEGIN TRY
    BEGIN TRANSACTION;
    DELETE dbo.caso;
    INSERT dbo.caso (origen, departamento, provincia, distrito, enfermedad, ano, semana, edad, sexo)
    SELECT DISTINCT 'ZOONOSIS', departamento, provincia, distrito, enfermedad,
           CAST(ano AS SMALLINT), CAST(semana AS TINYINT), TRY_CAST(NULLIF(edad,'') AS SMALLINT), dbo.fn_sexo(sexo)
    FROM stg.zoonosis_raw
    WHERE TRY_CAST(ano AS INT) BETWEEN 2000 AND YEAR(GETDATE()) AND TRY_CAST(semana AS INT) BETWEEN 1 AND 53
      AND (NULLIF(edad,'') IS NULL OR TRY_CAST(edad AS INT) BETWEEN 0 AND 120);
    SET @n1 = @@ROWCOUNT;

    SAVE TRANSACTION sp_dengue;
    SET @fase = 2;
    INSERT dbo.caso (origen, departamento, provincia, distrito, enfermedad, ano, semana, edad, sexo)
    SELECT DISTINCT 'DENGUE', departamento, provincia, distrito, enfermedad,
           CAST(ano AS SMALLINT), CAST(semana AS TINYINT), TRY_CAST(NULLIF(edad,'') AS SMALLINT), dbo.fn_sexo(sexo)
    FROM stg.dengue_raw
    WHERE TRY_CAST(ano AS INT) BETWEEN 2000 AND YEAR(GETDATE()) AND TRY_CAST(semana AS INT) BETWEEN 1 AND 53
      AND (NULLIF(edad,'') IS NULL OR TRY_CAST(edad AS INT) BETWEEN 0 AND 120);
    SET @n2 = @@ROWCOUNT;

    INSERT dbo.log_auditoria(objeto, operacion, detalle, estado)
    VALUES ('usp_cargar', 'INGESTA', CONCAT('Zoonosis: ', @n1, ' | Dengue: ', @n2), 'OK');
    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    DECLARE @msg NVARCHAR(300) = ERROR_MESSAGE();
    IF @fase = 2 AND XACT_STATE() = 1
    BEGIN
      ROLLBACK TRANSACTION sp_dengue;
      INSERT dbo.log_auditoria(objeto, operacion, detalle, estado)
      VALUES ('usp_cargar', 'INGESTA', CONCAT('Dengue fallo, zoonosis conservada: ', @msg), 'ADVERTENCIA');
      COMMIT TRANSACTION;
    END
    ELSE
    BEGIN
      IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
      INSERT dbo.log_auditoria(objeto, operacion, detalle, estado)
      VALUES ('usp_cargar', 'INGESTA', @msg, 'ERROR');
      THROW;
    END
  END CATCH
END;
GO