/* DATASALUD PERU - MODELO ANALITICO Y CARGA ETL
   Ejecutar DESPUES de 01 o 01B y 02. SQL Server 2017+.
   Granularidad: UNA FILA DE HECHOS POR REGISTRO AGREGADO DE LA FUENTE SIS.
   ATENCIONES es una medida agregada; NO representa pacientes individuales.
   La fecha es el primer dia del mes (la fuente solo trae ano/mes).
   El catalogo IPRESS es de otro corte temporal: enriquecimiento referencial,
   no prueba de situacion historica coincidente.
   Proceso repetible e idempotente: reconstruye hechos y dimensiones en transaccion.
*/
USE MINSA;
GO
IF NOT EXISTS(SELECT 1 FROM sys.schemas WHERE name=N'bi') EXEC(N'CREATE SCHEMA bi');
GO
IF OBJECT_ID(N'bi.DimTiempo',N'U') IS NULL
 CREATE TABLE bi.DimTiempo(
  TiempoKey INT NOT NULL PRIMARY KEY, FechaMes DATE NOT NULL UNIQUE,
  Ano SMALLINT NOT NULL, Mes TINYINT NOT NULL,
  CONSTRAINT CK_bi_Mes CHECK(Mes BETWEEN 1 AND 12));
IF OBJECT_ID(N'bi.DimUbicacion',N'U') IS NULL
 CREATE TABLE bi.DimUbicacion(
  UbicacionKey INT IDENTITY(1,1) PRIMARY KEY,
  Region NVARCHAR(200) NOT NULL, Provincia NVARCHAR(200) NOT NULL,
  Distrito NVARCHAR(200) NOT NULL, UbigeoDistrito NVARCHAR(20) NOT NULL,
  CONSTRAINT UQ_bi_Ubicacion UNIQUE(Region,Provincia,Distrito,UbigeoDistrito));
IF OBJECT_ID(N'bi.DimServicio',N'U') IS NULL
 CREATE TABLE bi.DimServicio(
  ServicioKey INT IDENTITY(1,1) PRIMARY KEY,
  CodigoServicio NVARCHAR(20) NOT NULL, Servicio NVARCHAR(100) NOT NULL,
  CONSTRAINT UQ_bi_Servicio UNIQUE(CodigoServicio,Servicio));
IF OBJECT_ID(N'bi.DimIPRESS',N'U') IS NULL
 CREATE TABLE bi.DimIPRESS(
  IPRESSKey INT IDENTITY(1,1) PRIMARY KEY,
  CodigoIPRESS NVARCHAR(30) NOT NULL UNIQUE, NombreIPRESS NVARCHAR(250) NOT NULL,
  Categoria NVARCHAR(100) NULL, EstadoCatalogo NVARCHAR(100) NULL);
IF OBJECT_ID(N'bi.FactAtenciones',N'U') IS NULL
 CREATE TABLE bi.FactAtenciones(
  IdAtencionFuente BIGINT NOT NULL PRIMARY KEY,
  TiempoKey INT NOT NULL REFERENCES bi.DimTiempo(TiempoKey),
  UbicacionKey INT NOT NULL REFERENCES bi.DimUbicacion(UbicacionKey),
  ServicioKey INT NOT NULL REFERENCES bi.DimServicio(ServicioKey),
  IPRESSKey INT NOT NULL REFERENCES bi.DimIPRESS(IPRESSKey),
  Sexo NVARCHAR(30) NOT NULL, GrupoEdad NVARCHAR(30) NOT NULL,
  PlanSeguro NVARCHAR(100) NULL, CantidadAtenciones BIGINT NOT NULL,
  CONSTRAINT CK_bi_Atenciones CHECK(CantidadAtenciones>=0));
IF OBJECT_ID(N'bi.LogETL',N'U') IS NULL
 CREATE TABLE bi.LogETL(
  IdLog BIGINT IDENTITY(1,1) PRIMARY KEY, Inicio DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  Fin DATETIME2 NULL, Estado NVARCHAR(20) NOT NULL,
  FilasOrigen BIGINT NULL, FilasHechos BIGINT NULL,
  TotalOrigen BIGINT NULL, TotalHechos BIGINT NULL,
  Detalle NVARCHAR(2000) NULL);
GO
CREATE OR ALTER PROCEDURE bi.sp_CargarModeloEstrella
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 DECLARE @Inicio DATETIME2=SYSDATETIME(),@Origen BIGINT,@TotalOrigen BIGINT,
         @Hechos BIGINT,@TotalHechos BIGINT;
 BEGIN TRY
  SELECT @Origen=COUNT_BIG(*),@TotalOrigen=COALESCE(SUM(ATENCIONES),0)
  FROM dbo.ATENCIONES_SIS_OFICIAL;
  IF @Origen=0 THROW 54001,N'Cargue primero la fuente oficial SIS.',1;
  BEGIN TRANSACTION;
  /* Las dimensiones se actualizan, sin borrar claves previas. */
  INSERT bi.DimTiempo(TiempoKey,FechaMes,Ano,Mes)
  SELECT DISTINCT S.ANO*100+S.MES,DATEFROMPARTS(S.ANO,S.MES,1),S.ANO,S.MES
  FROM dbo.ATENCIONES_SIS_OFICIAL AS S
  WHERE NOT EXISTS(SELECT 1 FROM bi.DimTiempo D WHERE D.TiempoKey=S.ANO*100+S.MES);

  INSERT bi.DimUbicacion(Region,Provincia,Distrito,UbigeoDistrito)
  SELECT DISTINCT S.REGION,S.PROVINCIA,S.DISTRITO,ISNULL(S.UBIGEO_DISTRITO,N'')
  FROM dbo.ATENCIONES_SIS_OFICIAL S
  WHERE NOT EXISTS(SELECT 1 FROM bi.DimUbicacion D
   WHERE D.Region=S.REGION AND D.Provincia=S.PROVINCIA AND D.Distrito=S.DISTRITO
     AND D.UbigeoDistrito=ISNULL(S.UBIGEO_DISTRITO,N''));

  INSERT bi.DimServicio(CodigoServicio,Servicio)
  SELECT DISTINCT ISNULL(S.COD_SERVICIO,N''),S.DESC_SERVICIO
  FROM dbo.ATENCIONES_SIS_OFICIAL S
  WHERE NOT EXISTS(SELECT 1 FROM bi.DimServicio D
    WHERE D.CodigoServicio=ISNULL(S.COD_SERVICIO,N'') AND D.Servicio=S.DESC_SERVICIO);

  /* Un catalogo de establecimientos no equivale a datos de pacientes. */
  INSERT bi.DimIPRESS(CodigoIPRESS,NombreIPRESS,Categoria,EstadoCatalogo)
  SELECT S.COD_IPRESS,MAX(S.IPRESS),MAX(I.CATEGORIA),MAX(I.ESTADO)
  FROM dbo.ATENCIONES_SIS_OFICIAL S
  LEFT JOIN ref.IPRESS_MINSA I ON I.CODIGO_UNICO=S.COD_IPRESS
  WHERE S.COD_IPRESS IS NOT NULL
    AND NOT EXISTS(SELECT 1 FROM bi.DimIPRESS D WHERE D.CodigoIPRESS=S.COD_IPRESS)
  GROUP BY S.COD_IPRESS;
  UPDATE D SET NombreIPRESS=COALESCE(I.NOMBRE_ESTABLECIMIENTO,D.NombreIPRESS),
    Categoria=I.CATEGORIA,EstadoCatalogo=I.ESTADO
  FROM bi.DimIPRESS D JOIN ref.IPRESS_MINSA I ON I.CODIGO_UNICO=D.CodigoIPRESS;

  /* Reconstruccion atomica de hechos: no duplica registros al reejecutar. */
  DELETE FROM bi.FactAtenciones;
  INSERT bi.FactAtenciones(IdAtencionFuente,TiempoKey,UbicacionKey,ServicioKey,
    IPRESSKey,Sexo,GrupoEdad,PlanSeguro,CantidadAtenciones)
  SELECT S.ID_ATENCION,S.ANO*100+S.MES,U.UbicacionKey,V.ServicioKey,P.IPRESSKey,
    S.SEXO,S.GRUPO_EDAD,S.PLAN_DE_SEGURO,S.ATENCIONES
  FROM dbo.ATENCIONES_SIS_OFICIAL S
  JOIN bi.DimUbicacion U ON U.Region=S.REGION AND U.Provincia=S.PROVINCIA
   AND U.Distrito=S.DISTRITO AND U.UbigeoDistrito=ISNULL(S.UBIGEO_DISTRITO,N'')
  JOIN bi.DimServicio V ON V.CodigoServicio=ISNULL(S.COD_SERVICIO,N'')
   AND V.Servicio=S.DESC_SERVICIO
  JOIN bi.DimIPRESS P ON P.CodigoIPRESS=S.COD_IPRESS;

  SELECT @Hechos=COUNT_BIG(*),@TotalHechos=COALESCE(SUM(CantidadAtenciones),0)
  FROM bi.FactAtenciones;
  IF @Hechos<>@Origen OR @TotalHechos<>@TotalOrigen
   THROW 54002,N'ETL sin conciliacion: difieren las filas o la suma de atenciones.',1;
  INSERT bi.LogETL(Inicio,Fin,Estado,FilasOrigen,FilasHechos,TotalOrigen,TotalHechos,Detalle)
  VALUES(@Inicio,SYSDATETIME(),N'CORRECTO',@Origen,@Hechos,@TotalOrigen,@TotalHechos,
    N'Carga de dimensiones e indicadores conciliados');
  COMMIT TRANSACTION;
  SELECT @Origen AS FilasOrigen,@Hechos AS FilasDW,@TotalOrigen AS AtencionesOrigen,
         @TotalHechos AS AtencionesDW;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
  INSERT bi.LogETL(Inicio,Fin,Estado,Detalle)
  VALUES(@Inicio,SYSDATETIME(),N'ERROR',ERROR_MESSAGE());
  THROW;
 END CATCH
END;
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'bi.FactAtenciones')
  AND name=N'IX_FactAtenciones_Tiempo_Servicio')
 CREATE INDEX IX_FactAtenciones_Tiempo_Servicio
 ON bi.FactAtenciones(TiempoKey,ServicioKey) INCLUDE(CantidadAtenciones);
GO
EXEC bi.sp_CargarModeloEstrella;
GO
/* Consulta BI: no atribuir estos agregados a personas individuales. */
SELECT T.Ano,T.Mes,U.Provincia,V.Servicio,SUM(F.CantidadAtenciones) AS TotalAtenciones
FROM bi.FactAtenciones F
JOIN bi.DimTiempo T ON T.TiempoKey=F.TiempoKey
JOIN bi.DimUbicacion U ON U.UbicacionKey=F.UbicacionKey
JOIN bi.DimServicio V ON V.ServicioKey=F.ServicioKey
GROUP BY T.Ano,T.Mes,U.Provincia,V.Servicio
ORDER BY TotalAtenciones DESC;
GO
