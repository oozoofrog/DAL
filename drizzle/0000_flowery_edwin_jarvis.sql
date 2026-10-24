CREATE TABLE `messages` (
	`id` text PRIMARY KEY NOT NULL,
	`thread_id` text NOT NULL,
	`kind` text NOT NULL,
	`body` text NOT NULL,
	`version_id` text,
	`created_by` text NOT NULL,
	`author_role` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`thread_id`) REFERENCES `threads`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`version_id`) REFERENCES `versions`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `operations` (
	`key` text PRIMARY KEY NOT NULL,
	`request_hash` text NOT NULL,
	`response_json` text NOT NULL,
	`guard` integer NOT NULL,
	`created_at` text NOT NULL,
	CONSTRAINT "operation_guard" CHECK("operations"."guard" = 1)
);
--> statement-breakpoint
CREATE TABLE `threads` (
	`id` text PRIMARY KEY NOT NULL,
	`version_id` text NOT NULL,
	`start_ms` integer NOT NULL,
	`end_ms` integer NOT NULL,
	`annotation_json` text NOT NULL,
	`intent` text NOT NULL,
	`status` text NOT NULL,
	`resolved` integer DEFAULT 0 NOT NULL,
	`revision` integer DEFAULT 0 NOT NULL,
	`result_message_id` text,
	`result_version_id` text,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`version_id`) REFERENCES `versions`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`result_version_id`) REFERENCES `versions`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `versions` (
	`id` text PRIMARY KEY NOT NULL,
	`label` text NOT NULL,
	`media_hash` text,
	`duration_ms` integer NOT NULL,
	`fps` real NOT NULL,
	`created_at` text NOT NULL
);
