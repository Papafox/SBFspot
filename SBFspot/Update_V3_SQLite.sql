-- V3.8.0 Update_V3_SQLite.sql
-- SchemaVersion 3
--
-- Fix Issue #137 Power value too high for system size 
-- Fix Issue #283 SBFspot Upload Performance
-- 

-- Add PVO SystemSize / InstallDate to Inverters Table
ALTER TABLE Inverters ADD COLUMN PvoSystemSize int;
ALTER TABLE Inverters ADD COLUMN PvoInstallDate varchar;

--
-- vwInverters View
--
DROP VIEW IF EXISTS vwInverters;

CREATE View vwInverters AS
	SELECT Serial,
	Name,Type,SW_Version,
	datetime(TimeStamp, 'unixepoch', 'localtime') AS TimeStamp,
	TotalPac,
	EToday,ETotal,
	OperatingTime,FeedInTime,
	Status,GridRelay,
	Temperature,
	PvoSystemSize, PvoInstallDate
	FROM Inverters;

--
-- vwPVODayData View
--
DROP VIEW IF EXISTS vwPVODayData;

CREATE VIEW vwPVODayData AS
	SELECT
		TimeStamp,
        Serial,
        TotalYield,
        Power
    FROM DayData Dat
    WHERE TimeStamp > strftime('%s', 'now') - (SELECT Value FROM Config WHERE [Key] = 'Batch_DateLimit') * 86400 
		AND PvOutput IS NULL;

--
-- vwPVOSpotData View
--
DROP VIEW IF EXISTS vwPVOSpotData;

CREATE VIEW vwPVOSpotData AS
	SELECT
		TimeStamp,
        TimeStamp - (TimeStamp % 300) AS Nearest5min,
        Serial,
        Pdc1,
        Pdc2,
        Idc1,
        Idc2,
        Udc1,
        Udc2,
        Pac1,
        Pac2,
        Pac3,
        Iac1,
        Iac2,
        Iac3,
        Uac1,
        Uac2,
        Uac3,
        Pdc1 + Pdc2 AS PdcTot,
        Pac1 + Pac2 + Pac3 AS PacTot,
        ROUND( Temperature, 1 ) AS Temperature
	FROM SpotData
    WHERE TimeStamp > strftime('%s', 'now') - (SELECT Value FROM Config WHERE [Key] = 'Batch_DateLimit') * 86400;

--
-- vwPVOSpotDataAvg View
--
DROP VIEW IF EXISTS vwPVOSpotDataAvg;

CREATE VIEW vwPVOSpotDataAvg AS
	SELECT
		nearest5min,
        serial,
        avg( Pdc1 ) AS Pdc1,
        avg( Pdc2 ) AS Pdc2,
        avg( Idc1 ) AS Idc1,
        avg( Idc2 ) AS Idc2,
        avg( Udc1 ) AS Udc1,
        avg( Udc2 ) AS Udc2,
        avg( Pac1 ) AS Pac1,
        avg( Pac2 ) AS Pac2,
        avg( Pac3 ) AS Pac3,
        avg( Iac1 ) AS Iac1,
        avg( Iac2 ) AS Iac2,
        avg( Iac3 ) AS Iac3,
        avg( Uac1 ) AS Uac1,
        avg( Uac2 ) AS Uac2,
        avg( Uac3 ) AS Uac3,
        avg( Temperature ) AS Temperature
	FROM vwPVOSpotData
    GROUP BY serial, nearest5min;

--
-- vwPVOUploadGeneration View
--
DROP VIEW IF EXISTS vwPVOUploadGeneration;

CREATE VIEW vwPVOUploadGeneration AS
	SELECT
		datetime( dd.TimeStamp, 'unixepoch', 'localtime' ) AS TimeStamp,
		dd.Serial,
		dd.TotalYield AS V1,
		CASE WHEN dd.Power > (IFNULL(inv.PvoSystemSize * 1.4, dd.Power))
			THEN 0 ELSE dd.Power END AS V2,
		NULL AS V3,
		NULL AS V4,
		CASE (SELECT Value FROM Config WHERE [Key] = 'PvoTemperature')
			WHEN 'Ambient' THEN NULL ELSE spot.Temperature END AS V5,
		spot.Uac1 AS V6,
		NULL AS V7,
		NULL AS V8,
		NULL AS V9,
		NULL AS V10,
		NULL AS V11,
		NULL AS V12
	FROM vwPVODayData AS dd
    LEFT JOIN vwPVOSpotDataAvg AS spot ON dd.Serial = spot.Serial AND dd.Timestamp = spot.Nearest5min
	LEFT JOIN Inverters AS inv ON dd.Serial = inv.Serial;

-- Define temperature to show at PVoutput (V5): Inverter or Ambient
INSERT OR IGNORE INTO Config (`Key`,`Value`) VALUES ('PvoTemperature','Inverter');

-- Update SchemaVersion if all is OK
UPDATE Config SET `Value` = '3' WHERE `Key` = 'SchemaVersion';
