-- this is an example of how one might implement history tables for MySQL.


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


-- Some comments on the implementation:
-- * It puts the history data in delegate tables so that most applications
--   can be fully unaware of the history logging.
-- * It uses a specific history table for each main table so that it is easy
--   to build reports / do joins with/across history tables
-- * It requires that all cross-table links are done using dedicated link
--   tables that themselves are versioned
-- * It keeps track of creation dates, modification dates, and users,
--   allowing the application to override the username
--   * beware - there's a bug in how the username is set for the update triggers!
-- * It results in a _lot_ of typing if you write all the tables and
--   triggers by hand; a typical real-life solution would script more of that
--
-- WARNING: this kind of schema is _not_ good enough by itself to satisfy an
-- _audit_, see
--   http://www.scribd.com/doc/2569459/Securing-MySQL-for-a-Security-Audit
-- for pointers on how to do auditable database stuff
--
-- WARNING: can cause problems with replication:
--   http://www.mysqlperformanceblog.com/2008/09/29/why-audit-logging-with-triggers-in-mysql-is-bad-for-replication/
-- use row-based replication to avoid those problems:
--   http://dev.mysql.com/doc/refman/5.1/en/replication-formats.html
--
-- Ideas for an alternative approach (using one big history table):
--   http://www.go4expert.com/forums/showthread.php?t=7252
--
-- Ideas for a compact way to generate trigger code:
--   http://thenoyes.com/littlenoise/?p=43


-- 'main' schema

CREATE TABLE mythings (
    id int(11) unsigned NOT NULL auto_increment PRIMARY KEY,
    somevalue varchar(255) DEFAULT NULL,
    othervalue varchar(255) DEFAULT NULL,
    
    created timestamp NULL DEFAULT NULL,
    modified timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    modifier varchar(255) DEFAULT NULL
) Engine=InnoDB;

CREATE TABLE others (
    id int(11) unsigned NOT NULL auto_increment PRIMARY KEY,
    
    created timestamp NULL DEFAULT NULL,
    modified timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    modifier varchar(255) DEFAULT NULL
) Engine=InnoDB;

CREATE TABLE mythings2others (
    mythings_id int(11) unsigned NOT NULL,
    others_id int(11) unsigned NOT NULL PRIMARY KEY,
    
    created timestamp NULL DEFAULT NULL,
    modified timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    modifier varchar(255) DEFAULT NULL,
    
    CONSTRAINT FOREIGN KEY (mythings_id)
      REFERENCES mythings (id)
      ON DELETE CASCADE
      ON UPDATE CASCADE,
    CONSTRAINT FOREIGN KEY (others_id)
      REFERENCES others (id)
      ON DELETE CASCADE
      ON UPDATE CASCADE
) Engine=InnoDB;

DELIMITER |
CREATE TRIGGER mythings_before_insert BEFORE INSERT ON mythings
  FOR EACH ROW BEGIN
    SET NEW.created = IFNULL(NEW.created, NOW());
  END
|
CREATE TRIGGER others_before_insert BEFORE INSERT ON others
  FOR EACH ROW BEGIN
    SET NEW.created = IFNULL(NEW.created, NOW());
  END
|
CREATE TRIGGER mythings2others_before_insert BEFORE INSERT ON mythings2others
  FOR EACH ROW BEGIN
    SET NEW.created = IFNULL(NEW.created, NOW());
  END
|
DELIMITER ;


-- history tracking for mythings

CREATE TABLE mythings_history (
    version int(11) unsigned NOT NULL auto_increment PRIMARY KEY,
    mythings_id int(11) unsigned NOT NULL,
    
    action varchar(16) NOT NULL,
    old_somevalue varchar(255) DEFAULT NULL,
    new_somevalue varchar(255) DEFAULT NULL,
    old_othervalue varchar(255) DEFAULT NULL,
    new_othervalue varchar(255) DEFAULT NULL,
    modified timestamp NULL DEFAULT NULL,
    modifier varchar(255) DEFAULT NULL
) Engine=InnoDB;

DELIMITER |
CREATE TRIGGER mythings_after_insert AFTER INSERT ON mythings
  FOR EACH ROW BEGIN
    INSERT INTO mythings_history
            (mythings_id,
            action,
            old_somevalue,
            new_somevalue,
            old_othervalue,
            new_othervalue,
            modified,
            modifier)
        VALUES
            (NEW.id,
            'INSERT',
            NULL,
            NEW.somevalue,
            NULL,
            NEW.othervalue,
            NEW.modified,
            IFNULL(NEW.modifier,USER()));
  END
|
CREATE TRIGGER mythings_after_update AFTER UPDATE ON mythings
  FOR EACH ROW BEGIN
    INSERT INTO mythings_history
            (mythings_id,
            action,
            old_somevalue,
            new_somevalue,
            old_othervalue,
            new_othervalue,
            modified,
            modifier)
        VALUES
            (NEW.id,
            'UPDATE',
            OLD.somevalue,
            NEW.somevalue,
            OLD.othervalue,
            NEW.othervalue,
            NEW.modified,
            IFNULL(NEW.modifier,USER()));
  END
|
CREATE TRIGGER mythings_after_delete AFTER DELETE ON mythings
  FOR EACH ROW BEGIN
    INSERT INTO mythings_history
        (mythings_id,
        action,
        old_somevalue,
        new_somevalue,
        old_othervalue,
        new_othervalue,
        modified,
        modifier)
    VALUES
        (OLD.id,
        'DELETE',
        OLD.somevalue,
        NULL,
        OLD.othervalue,
        NULL,
        NOW(),
        USER());
  END
|
DELIMITER ;


-- history tracking for others

CREATE TABLE others_history (
    version int(11) unsigned NOT NULL auto_increment PRIMARY KEY,
    others_id int(11) unsigned NOT NULL,
    
    action varchar(16) NOT NULL,
    modified timestamp NULL DEFAULT NULL,
    modifier varchar(255) DEFAULT NULL
) Engine=InnoDB;

DELIMITER |
CREATE TRIGGER others_after_insert AFTER INSERT ON others
  FOR EACH ROW BEGIN
    INSERT INTO others_history
            (others_id,
            action,
            modified,
            modifier)
        VALUES
            (NEW.id,
            'INSERT',
            NEW.modified,
            IFNULL(NEW.modifier,USER()));
  END
|
CREATE TRIGGER others_after_update AFTER UPDATE ON others
  FOR EACH ROW BEGIN
    INSERT INTO others_history
            (others_id,
            action,
            modified,
            modifier)
        VALUES
            (NEW.id,
            'UPDATE',
            NEW.modified,
            IFNULL(NEW.modifier,USER()));
  END
|
CREATE TRIGGER others_after_delete AFTER DELETE ON others
  FOR EACH ROW BEGIN
    INSERT INTO others_history
        (others_id,
        action,
        modified,
        modifier)
    VALUES
        (OLD.id,
        'DELETE',
        NOW(),
        USER());
  END
|
DELIMITER ;


-- history tracking for mythings2others

CREATE TABLE mythings2others_history (
    version int(11) unsigned NOT NULL auto_increment PRIMARY KEY,
    old_mythings_id int(11) unsigned DEFAULT NULL,
    new_mythings_id int(11) unsigned DEFAULT NULL,
    mythings_history_version int(11) unsigned DEFAULT NULL,
    old_others_id int(11) unsigned DEFAULT NULL,
    new_others_id int(11) unsigned DEFAULT NULL,
    others_history_version int(11) unsigned DEFAULT NULL,

    action varchar(16) NOT NULL,
    modified timestamp NULL DEFAULT NULL,
    modifier varchar(255) DEFAULT NULL
) Engine=InnoDB;

DELIMITER |
CREATE TRIGGER mythings2others_after_insert AFTER INSERT ON mythings2others
  FOR EACH ROW BEGIN
    INSERT INTO mythings2others_history
            (old_mythings_id,
            new_mythings_id,
            mythings_history_version,
            old_others_id,
            new_others_id,
            others_history_version,
            action,
            modified,
            modifier)
        VALUES
            (NULL,
            NEW.mythings_id,
            (SELECT version FROM mythings_history WHERE mythings_id = NEW.mythings_id ORDER BY version DESC LIMIT 1),
            NULL,
            NEW.others_id,
            (SELECT version FROM others_history WHERE others_id = NEW.others_id ORDER BY version DESC LIMIT 1),
            'INSERT',
            NEW.modified,
            IFNULL(NEW.modifier,USER()));
  END
|
CREATE TRIGGER mythings2others_after_update AFTER UPDATE ON mythings2others
  FOR EACH ROW BEGIN
    INSERT INTO mythings2others_history
            (old_mythings_id,
            new_mythings_id,
            mythings_history_version,
            old_others_id,
            new_others_id,
            others_history_version,
            action,
            modified,
            modifier)
        VALUES
            (OLD.mythings_id,
            NEW.mythings_id,
            (SELECT version FROM mythings_history WHERE mythings_id = NEW.mythings_id ORDER BY version DESC LIMIT 1),
            OLD.mythings_id,
            NEW.others_id,
            (SELECT version FROM others_history WHERE others_id = NEW.others_id ORDER BY version DESC LIMIT 1),
            'UPDATE',
            NEW.modified,
            IFNULL(NEW.modifier,USER()));
  END
|
CREATE TRIGGER mythings2others_after_delete AFTER DELETE ON mythings2others
  FOR EACH ROW BEGIN
    INSERT INTO mythings2others_history
            (old_mythings_id,
            new_mythings_id,
            mythings_history_version,
            old_others_id,
            new_others_id,
            others_history_version,
            action,
            modified,
            modifier)
        VALUES
            (OLD.mythings_id,
            NULL,
            (SELECT version FROM mythings_history WHERE mythings_id = OLD.mythings_id ORDER BY version DESC LIMIT 1),
            OLD.mythings_id,
            NULL,
            (SELECT version FROM others_history WHERE others_id = OLD.others_id ORDER BY version DESC LIMIT 1),
            'DELETE',
            NOW(),
            USER());
  END
|
DELIMITER ;


-- some sample data

INSERT INTO mythings (somevalue, modifier) VALUES ('blah', 'mail@leosimons.com');
INSERT INTO mythings (somevalue, modifier) VALUES ('second thing', 'mail@leosimons.com');
UPDATE mythings SET othervalue = 'things are the same', modifier = 'mail@leosimons.com';
INSERT INTO others (modifier) VALUES ('mail@leosimons.com');
INSERT INTO others (modifier) VALUES ('mail@leosimons.com');
INSERT INTO mythings2others (mythings_id, others_id, modifier) VALUES (1, 1, 'mail@leosimons.com');
UPDATE mythings2others SET mythings_id = 2, modifier = 'mail@leosimons.com' WHERE mythings_id = 1 LIMIT 1;
