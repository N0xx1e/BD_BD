
EXEC dbo.usp_validar;
EXEC dbo.usp_cargar;
GO
BEGIN TRY
  INSERT dbo.caso (origen, ano, semana, edad) VALUES ('DENGUE', 1999, 60, 200);
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje; END CATCH
GO
SELECT origen, COUNT(*) AS filas FROM dbo.caso GROUP BY origen;
SELECT * FROM dbo.log_auditoria ORDER BY id_log;
