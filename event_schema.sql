-- this is a 'silly' example of how one might implement a backend for a message
-- queue system using MySQL. It's not recommended that you actually try and do
-- anything like this :-)



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

CREATE TABLE queues (
   name varchar(64) NOT NULL,

   PRIMARY KEY queues_pk (name)
);

CREATE TABLE subscriptions (
   subscriber varchar(64) NOT NULL,
   subscribed varchar(64) NOT NULL,
   created timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

   PRIMARY KEY subscriptions_pk (subscriber, subscribed),
   INDEX subscriptions_reverse (subscribed, subscriber)
);

CREATE TABLE events (
   id int(11) unsigned NOT NULL auto_increment,
   occurred timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
   source_queue varchar(64) NOT NULL,
   data text NOT NULL,
   notifications_complete tinyint(1) NOT NULL DEFAULT 0,

   PRIMARY KEY events_pk (id),
   INDEX events_by_queue_by_created (source_queue, occurred)
);

CREATE TABLE notifications (
   id int(11) unsigned NOT NULL auto_increment,
   notified timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
   event_id varchar(64) NOT NULL,
   target_queue varchar(64) NOT NULL,
   push_complete tinyint(1) NOT NULL DEFAULT 0,

   PRIMARY KEY notifications_pk (id),
   INDEX notifications_by_queue_by_created (target_queue, notified)
);

DELIMITER |
CREATE PROCEDURE notify_of_events()
BEGIN
   DECLARE done bool DEFAULT FALSE;
   DECLARE my_event_id int(11) unsigned;
   DECLARE my_event_queue varchar(64);
   DECLARE my_cursor CURSOR FOR SELECT
           id, source_queue
       FROM events
       WHERE notifications_complete = 0;
   DECLARE CONTINUE HANDLER FOR SQLSTATE '02000'
       SET done = TRUE;

   OPEN my_cursor;
   my_loop: LOOP
       FETCH my_cursor INTO my_event_id, my_event_queue;

       IF done THEN
           CLOSE my_cursor;
           LEAVE my_loop;
       END IF;

       INSERT INTO notifications (event_id, target_queue)
           SELECT
               my_event_id, s.subscriber
           FROM subscriptions s
           WHERE s.subscribed = my_event_queue;

       UPDATE events SET notifications_complete = 1 WHERE id = my_event_id;
   END LOOP;

END
|

-- this ought to be done from application code....
CREATE PROCEDURE dummy_push_notifications()
BEGIN
   DECLARE done bool DEFAULT FALSE;
   DECLARE my_notification_id int(11) unsigned;
   DECLARE my_cursor CURSOR FOR SELECT id
       FROM notifications
       WHERE push_complete = 0;
   DECLARE CONTINUE HANDLER FOR SQLSTATE '02000'
       SET done = TRUE;

   OPEN my_cursor;
   my_loop: LOOP
       FETCH my_cursor INTO my_notification_id;

       IF done THEN
           CLOSE my_cursor;
           LEAVE my_loop;
       END IF;

       -- would do something here, like send e-mail

       UPDATE notifications SET push_complete = 1 WHERE id = my_notification_id;
   END LOOP;

END
|

DELIMITER ;

-- from user signing up, i.e. user clicks "register"
INSERT INTO queues (name) values ('steveswrong');
INSERT INTO queues (name) values ('lsd');
INSERT INTO queues (name) values ('aaron');

-- from preferences APIs, i.e. user clicks "follow"
INSERT INTO subscriptions (subscriber, subscribed) values ('steveswrong', 'lsd');
INSERT INTO subscriptions (subscriber, subscribed) values ('steveswrong', 'aaron');
INSERT INTO subscriptions (subscriber, subscribed) values ('lsd', 'aaron');
INSERT INTO subscriptions (subscriber, subscribed) values ('lsd', 'steveswrong');
INSERT INTO subscriptions (subscriber, subscribed) values ('aaron', 'steveswrong');

-- from publish APIs, i.e. users types stuff in
INSERT INTO events (source_queue,data)
   VALUES ('steveswrong', 'favorited 00kifc7j5bvxc');
INSERT INTO events (source_queue,data)
   VALUES ('steveswrong', 'favorited 00ms2wlkhuqu8');

-- from a cron job
CALL notify_of_events();
CALL dummy_push_notifications();
CALL dummy_push_notifications();
CALL notify_of_events();

-- from the web page listing my events
SELECT * FROM notifications n
    INNER JOIN events e on n.event_id = e.id
    WHERE n.target_queue = 'lsd';
