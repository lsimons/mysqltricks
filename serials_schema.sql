-- this is a partial example of how one might use 64-bit random identifiers (as
-- opposed to the more common serial identifiers) within MySQL. Blog post at
--    http://lsimons.wordpress.com/2009/03/22/short-identifier-scheme/
-- for context.


-- Copyright (c) 2009 Leo Simons. All Rights Reserved.
-- 
-- Licensed under the Common Development and Distribution License, Version 1.0
-- (the "License"); you may not use this file except in compliance with the
-- License. You may obtain a copy of the License at
--    http://www.jicarilla.nl/licensing/
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
-- WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
-- License for the specific language governing permissions and limitations under
-- the License.

CREATE FUNCTION encode_id (n BIGINT) RETURNS char(13) NO SQL
  RETURN LPAD( LOWER(CONV(n,10,36)), 13, '0');

CREATE FUNCTION decode_id (n char(13)) RETURNS BIGINT NO SQL
  RETURN CONV(n,36,10);

CREATE FUNCTION gen_num_id () RETURNS BIGINT NO SQL
  RETURN FLOOR(RAND() * 184467440737095516);

CREATE FUNCTION gen_id () RETURNS char(13) NO SQL
  RETURN encode_id( gen_num_id() );

CREATE TABLE ids (
  -- this table should not be updated directly by apps,
  --   though they are expected to read from it
  numid BIGINT unsigned NOT NULL PRIMARY KEY,
  id char(13) NOT NULL UNIQUE,
  prettyid varchar(64) DEFAULT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE mythings (
  numid BIGINT unsigned NOT NULL PRIMARY KEY,
  id char(13) NOT NULL UNIQUE,
  prettyid varchar(64) DEFAULT NULL UNIQUE,
  something varchar(255) DEFAULT NULL
) ENGINE=InnoDB;

CREATE TABLE mythings2ids (
  -- this table should not be updated directly by apps,
  --   though its ok if they read from it
  numid BIGINT unsigned NOT NULL PRIMARY KEY,
  CONSTRAINT FOREIGN KEY (numid)
    REFERENCES ids (numid)
    ON DELETE cascade
    ON UPDATE cascade,
  CONSTRAINT FOREIGN KEY (numid)
    REFERENCES mythings (numid)
    ON DELETE cascade
    ON UPDATE cascade
) ENGINE=InnoDB;

DELIMITER |
CREATE TRIGGER mythings_before_insert BEFORE INSERT ON mythings
  FOR EACH ROW BEGIN
    INSERT INTO ids (numid,id,prettyid) VALUES (NEW.numid, NEW.id, NEW.prettyid);
  END
|
CREATE TRIGGER mythings_after_insert AFTER INSERT ON mythings
  FOR EACH ROW BEGIN
   INSERT INTO mythings2ids (numid) VALUES (NEW.numid);
  END
|
CREATE TRIGGER mythings_before_update BEFORE UPDATE ON mythings
  FOR EACH ROW BEGIN
    IF NEW.numid != OLD.numid THEN
      CALL CANNOT_CHANGE_NUMID_AFTER_CREATION;
    END IF;
    IF NEW.id != OLD.id THEN
      CALL CANNOT_CHANGE_ID_AFTER_CREATION;
    END IF;
    IF NEW.prettyid != OLD.prettyid THEN
      IF OLD.prettyid IS NOT NULL THEN
        CALL CANNOT_CHANGE_PRETTYID_AFTER_INIT;
      ELSE
        UPDATE ids SET prettyid = NEW.prettyid
          WHERE numid = NEW.numid LIMIT 1;
      END IF;
    END IF;
  END
|
CREATE TRIGGER mythings_after_delete AFTER DELETE ON mythings
  FOR EACH ROW BEGIN
   DELETE FROM ids WHERE numid = OLD.numid LIMIT 1;
  END
|
DELIMITER ;

-- SELECT gen_id() INTO @nextid;
-- INSERT INTO mythings (numid,id,prettyid,something)
--   VALUES (decode_id(@nextid),@nextid,
--       '2009/03/22/safe-id-names2','blah blah blah');