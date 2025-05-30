## AWS Deep Glacier Bundle Code ##
Author: JD Maloney

Purpose: Takes a directory path as an argument and does the following
* Records all files and their md5sums into a manifest file
* Tar bundles the directory into a single file and records its checksum
* Uses pgp to encrypt and compress the data bundle and a copy of the manifest
* Keeps an unencrypted manifest copy locally
* Ships the encrypted/compressed data bundle and an encrypted/compressed manifest to AWS Deep Glacier
* Records all information in the MariaDB database
* Removes all write permissions on the directory (removing write bits for owner/group/anonymous) following upload


Features:
* Tracks checksums throughout the chain and records them for posterity
* Encrypts and compresses data before shipping to AWS Deep Glacier
	- For security/privacy reasons, only you have your key
	- Reduces usage on AWS Deep Glacier to save money
* Obfuscates file names by uploading bundles that are named with incremental numbers
	- No paths or sensitive data in the file names for security/privacy reasons
* Removes write access to directory follow upload to help ensure data that has been uploaded isn't modified later 
* Included .json file can be uploadeed to a Grafana instance connected to your DB so you visualize archive stats


Requirements:
* Make sure following commands are available: "md5sum", "tar", "find", "gpg", "cp", "aws", "mysql"
* Generate a gpg key via "gpg --gen-key"
	- Save this key somewhere else that is safe (and possibly multiple places)
	- ** KEY IS NEEDED TO DECRYPT DATA WHEN RESTORING FROM THESE BACKUPS **
* Run "aws configure" to setup the awscli with your aws accsess key/secret/region definitions
* Create a MariaDB/MySQL database (named whatever you'd like, just place in the config)
	- Populate the DB with a single table named "bundle information" that described below:

```
MariaDB [aws_backup]> describe bundle_information;
+--------------------------------------+--------------+------+-----+---------+-------+
| Field                                | Type         | Null | Key | Default | Extra |
+--------------------------------------+--------------+------+-----+---------+-------+
| file_path_bundled                    | varchar(200) | NO   | PRI | NULL    |       |
| bundle_number                        | varchar(7)   | NO   |     | NULL    |       |
| bundle_file_name                     | varchar(200) | NO   |     | NULL    |       |
| bundle_file_md5sum                   | varchar(50)  | NO   |     | NULL    |       |
| bundle_encrypted_file_md5sum         | varchar(50)  | NO   |     | NULL    |       |
| bundle_file_date_created             | varchar(20)  | NO   |     | NULL    |       |
| bundle_file_size_bytes               | bigint(20)   | NO   |     | NULL    |       |
| bundle_encrypted_size_bytes          | bigint(20)   | NO   |     | NULL    |       |
| bundle_manifest_size_bytes           | bigint(20)   | NO   |     | NULL    |       |
| bundle_manifest_encrypted_size_bytes | bigint(20)   | NO   |     | NULL    |       |
| bundle_files_contained               | bigint(20)   | NO   |     | NULL    |       |
| bundle_manifest_path                 | varchar(200) | NO   |     | NULL    |       |
| total_bytes_to_aws                   | bigint(20)   | NO   |     | NULL    |       |
+--------------------------------------+--------------+------+-----+---------+-------+
```
