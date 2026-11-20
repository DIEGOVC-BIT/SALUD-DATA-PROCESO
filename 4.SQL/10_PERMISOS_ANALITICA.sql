/* DATASALUD PERU - PERMISOS DE ACCESO AL MODELO ANALITICO.
   Ejecutar DESPUES de 03 y 07; administrador debe aprobar accesos reales.
*/
USE MINSA;
GO
IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name=N'Role_Analista')
 THROW 54020,N'Primero ejecute 03_SEGURIDAD_ROLES_BACKUP_OFICIAL.sql.',1;
GRANT SELECT ON SCHEMA::bi TO Role_Analista;
GRANT SELECT ON SCHEMA::bi TO Role_Auditor;
GRANT SELECT ON SCHEMA::bi TO Role_Administrador;
GRANT EXECUTE ON OBJECT::bi.sp_CargarModeloEstrella TO Role_Administrador;
/* El analista ve resultados agregados y no modifica la base de datos BI. */
DENY INSERT, UPDATE, DELETE ON SCHEMA::bi TO Role_Analista;
DENY INSERT, UPDATE, DELETE ON SCHEMA::bi TO Role_Auditor;
GO
