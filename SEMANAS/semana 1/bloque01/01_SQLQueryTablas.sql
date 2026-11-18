USE DataSaludPeru;
GO
IF OBJECT_ID('dbo.log_auditoria') IS NULL
CREATE TABLE dbo.log_auditoria (
  id_log INT IDENTITY PRIMARY KEY,
  fecha_hora DATETIME2 DEFAULT SYSDATETIME(),
  usuario SYSNAME DEFAULT ORIGINAL_LOGIN(),
  objeto VARCHAR(50), operacion VARCHAR(20), detalle NVARCHAR(300), estado VARCHAR(12)
);
GO
IF OBJECT_ID('dbo.caso') IS NULL
CREATE TABLE dbo.caso (
  id_caso INT IDENTITY PRIMARY KEY,
  origen VARCHAR(10) NOT NULL,
  departamento VARCHAR(100), provincia VARCHAR(100), distrito VARCHAR(100), enfermedad VARCHAR(150),
  ano SMALLINT NOT NULL, semana TINYINT NOT NULL, edad SMALLINT NULL, sexo CHAR(1) NULL
);
GO
