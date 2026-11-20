/* DATASALUD PERU - SEGURIDAD Y RESPALDOS
   Ejecutar como administrador de MINSA. Crear previamente C:\BackUp_MINSA\
   y conceder permisos de escritura al servicio SQL Server.

   Referencia legal: Ley 29733, arts. 9 (seguridad), 16 (seguridad del tratamiento)
   y 17 (confidencialidad). El art. 11 corresponde al nivel de proteccion adecuado
   para flujo transfronterizo, no a los logs. Reglamento vigente: D.S. 016-2024-JUS.
*/
USE MINSA;
GO

/* 1. Tres roles con privilegios diferenciados. */
IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name=N'Role_Administrador') CREATE ROLE Role_Administrador;
IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name=N'Role_Analista') CREATE ROLE Role_Analista;
IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name=N'Role_Auditor') CREATE ROLE Role_Auditor;
GO

/* Administrador operativo: administra datos oficiales y ejecuta procesos ETL.
   No se le concede db_owner; se aplica minimo privilegio. */
GRANT SELECT,INSERT,UPDATE,DELETE ON dbo.ATENCIONES_SIS_OFICIAL TO Role_Administrador;
GRANT SELECT ON ref.IPRESS_MINSA TO Role_Administrador;
GRANT SELECT,INSERT,UPDATE,DELETE ON stg.SIS_ATENCIONES_RAW TO Role_Administrador;
GRANT SELECT,INSERT,UPDATE,DELETE ON stg.MINSA_IPRESS_RAW TO Role_Administrador;
GRANT EXECUTE ON OBJECT::ds.sp_ValidarStagingSIS TO Role_Administrador;
GRANT EXECUTE ON OBJECT::ds.sp_CargarAtencionesSISOficial TO Role_Administrador;
GRANT EXECUTE ON OBJECT::ds.sp_ActualizarCatalogoIPRESS TO Role_Administrador;
GRANT SELECT ON ds.Log_EjecucionOficial TO Role_Administrador;
GRANT SELECT ON ds.SIS_RECHAZOS TO Role_Administrador;
GRANT SELECT ON ds.Log_AuditoriaSIS TO Role_Administrador;
GO

/* Analista: lectura y consulta; sin permiso para alterar las fuentes. */
GRANT SELECT ON dbo.ATENCIONES_SIS_OFICIAL TO Role_Analista;
GRANT SELECT ON ref.IPRESS_MINSA TO Role_Analista;
GRANT EXECUTE ON OBJECT::ds.fn_ClasificarDemandaSIS TO Role_Analista;
DENY INSERT,UPDATE,DELETE ON dbo.ATENCIONES_SIS_OFICIAL TO Role_Analista;
DENY INSERT,UPDATE,DELETE ON ref.IPRESS_MINSA TO Role_Analista;
DENY SELECT ON ds.Log_AuditoriaSIS TO Role_Analista;
GO

/* Auditor: lectura de datos y bitacoras; sin permisos de modificacion. */
GRANT SELECT ON dbo.ATENCIONES_SIS_OFICIAL TO Role_Auditor;
GRANT SELECT ON ref.IPRESS_MINSA TO Role_Auditor;
GRANT SELECT ON ds.Log_EjecucionOficial TO Role_Auditor;
GRANT SELECT ON ds.SIS_RECHAZOS TO Role_Auditor;
GRANT SELECT ON ds.Log_AuditoriaSIS TO Role_Auditor;
DENY INSERT,UPDATE,DELETE ON dbo.ATENCIONES_SIS_OFICIAL TO Role_Auditor;
DENY INSERT,UPDATE,DELETE ON ref.IPRESS_MINSA TO Role_Auditor;
DENY INSERT,UPDATE,DELETE ON ds.Log_AuditoriaSIS TO Role_Auditor;
GO

/* Asociar usuarios existentes (descomentar y reemplazar por los usuarios reales):
ALTER ROLE Role_Administrador ADD MEMBER [usuario_admin_minsa];
ALTER ROLE Role_Analista ADD MEMBER [usuario_analista_minsa];
ALTER ROLE Role_Auditor ADD MEMBER [usuario_auditor_minsa];
*/

/* 2. Respaldo FULL + DIFFERENTIAL. No ejecutar si la carpeta no existe. */
BACKUP DATABASE MINSA
TO DISK=N'C:\BackUp_MINSA\MINSA_Full.bak'
WITH INIT,CHECKSUM,STATS=10,NAME=N'DataSalud MINSA FULL';
GO
BACKUP DATABASE MINSA
TO DISK=N'C:\BackUp_MINSA\MINSA_Diff.bak'
WITH DIFFERENTIAL,INIT,CHECKSUM,STATS=10,NAME=N'DataSalud MINSA DIFFERENTIAL';
GO

/* 3. Verificacion de legibilidad de los respaldos. Esto NO sustituye la
      restauracion real en una base separada. */
RESTORE VERIFYONLY FROM DISK=N'C:\BackUp_MINSA\MINSA_Full.bak' WITH CHECKSUM;
GO
RESTORE VERIFYONLY FROM DISK=N'C:\BackUp_MINSA\MINSA_Diff.bak' WITH CHECKSUM;
GO
