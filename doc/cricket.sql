/* This will create a table for use in storing Cricket data. This must be run
 * in a database called 'cricket' for the collector script to run properly.
 * 
 * Set it up with your own size parameters. Cricket doesn't insert a large
 * amount of data and this is really only good for warehousing as there is
 * no kind of calculations or interpolation done - data is simply dumped from
 * Cricket into the DB.
 *
 * This will work with Microsoft SQLServer. I do not know if it'll work with 
 * Sybase or any other type of database. If you have a version for another DB
 * please submit a patch so we can integrate it.
 */

CREATE TABLE [dbo].[CricketData] (
	[targetPath] [varchar] (256) NOT NULL ,
	[targetName] [varchar] (256) NOT NULL ,
	[ds] [int] NOT NULL ,
	[value] [int] NOT NULL ,
	[id] [int] IDENTITY (1, 1) NOT NULL ,
	[TimeStamp] [datetime] NOT NULL
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[CricketData] WITH NOCHECK ADD
	CONSTRAINT [IX_CricketData] UNIQUE NONCLUSTERED
	(
		[TimeStamp],
		[ds],
	) ON [PRIMARY]
GO
