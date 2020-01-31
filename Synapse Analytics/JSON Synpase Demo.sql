
-- Create the file format
CREATE EXTERNAL FILE FORMAT [Custom_delimited] WITH (FORMAT_TYPE = DELIMITEDTEXT, FORMAT_OPTIONS (FIELD_TERMINATOR = N'\n', USE_TYPE_DEFAULT = True))

-- Create the external data source (ADLS or BLOB)
CREATE EXTERNAL DATA SOURCE [AzBlob] WITH (TYPE = HADOOP, LOCATION = N'wasbs://bus@synstore.blob.core.windows.net', CREDENTIAL = [MSPOC])

-- Create the External table that will point to the Blob Storage or ADLS Gen 2
CREATE EXTERNAL TABLE [Ext].[TelemetryData](
	[json] [varchar](max) NOT NULL)
WITH (DATA_SOURCE = [AzBlob], LOCATION = N'/data',FILE_FORMAT = [Custom_delimited], REJECT_TYPE = VALUE, REJECT_VALUE = 0)

-- Create the Staging (interim) Table
Create table [stage].[TelemetryData](
	id int identity(1,1)
	,[json] varchar(max))
with (distribution = round_robin, HEAP)

--Start
--Bring JSON Raw Data into Staging
Truncate Table [stage].[TelemetryData]

Insert into [Stage].[TelemetryData]
select [json] from [Ext].[TelemetryData]

-- Copy from External Table to Stage
COPY INTO stage.TelemetryData_test ([json] 1)
FROM 'https://synstore.blob.core.windows.net:443/bus/data/'
WITH (
    FILE_TYPE = 'CSV',
    CREDENTIAL=(IDENTITY= 'Storage Account Key', SECRET='=YOURSECRET===='),
	--FIELDQUOTE = '"',
    FIELDTERMINATOR=',',
    ROWTERMINATOR = '\n',
	Identity_INSERT = 'OFF'
);
-- Flatten down JSON data
drop table [dbo].[TelemetryData_ETL];

Create Table [dbo].[TelemetryData_ETL] 
With(distribution = Hash(id), HEAP)
as select id
		, case when cast(JSON_VALUE(t.[json], '$.Device.App.RunTime.CallStatus') as varchar(50)) is null then '' else 'CallStatus' end as  [JsonType]
		, cast(JSON_VALUE(t.[json], '$.Device.App.RunTime.CallStatus') as varchar(50)) [CallStatus]
		, cast(JSON_VALUE(t.[json],'$.Cid') as nvarchar(40)) Cid
		, cast(JSON_VALUE(t.[json],'$.receivedbysajob') as datetime2) receivedbysajob 
		, cast(JSON_VALUE(t.[json],'$.EventEnqueuedUtcTime') as datetime2) AS EventEnqueuedUtcTime
from [dbo].[TelemetryData] t;

-- Add columnstore index

Create clustered Columnstore index cci_dbo_TelemetryData_ETL on [dbo].[TelemetryData_ETL]

Create Statistics stat_dbo_TelemetryData_ETL_id on [dbo].[TelemetryData_ETL](id) with fullscan
Create Statistics stat_dbo_TelemetryData_ETL_jsonType on [dbo].[TelemetryData_ETL](JsonType) with fullscan
Create Statistics stat_dbo_TelemetryData_ETL_CallStatus on [dbo].[TelemetryData_ETL]([CallStatus]) with fullscan
Create Statistics stat_dbo_TelemetryData_ETL_cid on [dbo].[TelemetryData_ETL]([Cid]) with fullscan
Create Statistics stat_dbo_TelemetryData_ETL_receivedbysajob on [dbo].[TelemetryData_ETL](receivedbysajob) with fullscan
Create Statistics stat_dbo_TelemetryData_ETL_EventEnqueuedUtcTime on [dbo].[TelemetryData_ETL](EventEnqueuedUtcTime) with fullscan

