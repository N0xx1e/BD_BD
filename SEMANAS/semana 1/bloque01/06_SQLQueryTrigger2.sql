CREATE OR ALTER TRIGGER dbo.trg_caso_integ ON dbo.caso
AFTER INSERT, UPDATE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS (SELECT 1 FROM inserted
             WHERE ano NOT BETWEEN 2000 AND YEAR(GETDATE()) OR semana NOT BETWEEN 1 AND 53 OR edad NOT BETWEEN 0 AND 120)
  BEGIN
    ROLLBACK TRANSACTION;
    INSERT dbo.log_auditoria(objeto, operacion, detalle, estado)
    VALUES ('trg_caso_integ', 'RECHAZO', 'Ano, semana o edad invalidos', 'ERROR');
    THROW 50001, 'Violacion de integridad en dbo.caso', 1;
  END
END;
GO