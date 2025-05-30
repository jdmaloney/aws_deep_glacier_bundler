#!/bin/bash

## Commands needed: md5sum tar find gpg cp aws mysql

## Load configuration
source ./config

## Input Related Variable Definitions
bundle_dir=$1

## Getting Dir Size
size=$(du -h --max-depth=0 ${bundle_dir} | awk '{print $1}')
echo "$(date) -- Data to be bundled: ${size}"

## Generate File List
echo "$(date) -- Generating file list"
find ${bundle_dir} -type f > ${bundle_build_dir}/aws_bundle_list.txt
rc=$?
if [ ${rc} -ne 0 ]; then
	exit 1
fi

## Get bundle file prefix
last_bundle_num=$(mysql -u $dbuser -p${dbpassword} -h ${dbhost} -D ${dbname} -e "select max(bundle_number) from bundle_information;" 2> /dev/null | grep -v bundle_number)

if [ "${last_bundle_num}" != "NULL" ]; then
        raw_num=$(echo $last_bundle_num | sed 's/^0*//')
        incremented_num=$((raw_num+1))
        prefix=$(printf %07d "$incremented_num")
else
	prefix="0000001"
fi

## Create checksum manifest list
echo "$(date) -- Gathering all file md5sums"
while IFS= read -r line; do
        md5sum=$(md5sum "${line}" | awk '{print $1}')
        echo "${md5sum} ${line}" >> ${bundle_build_dir}/${prefix}_manifest.txt
done < "${bundle_build_dir}/aws_bundle_list.txt"

## Create Archive Bundle
echo "$(date) -- Creating unencrypted data bundle"
tar -cvf ${bundle_build_dir}/${prefix}.tar ${bundle_dir} > /dev/null 2>&1
rc=$?
if [ ${rc} -ne 0 ]; then
	rm -f ${bundle_build_dir}/aws_bundle_list.txt
	rm -f ${bundle_build_dir}/${prefix}_manifest.txt
	exit 1
fi

## Checksum of Actual Bundle
echo "$(date) -- Checksumming the unencrypted data bundle"
real_md5sum=$(md5sum ${bundle_build_dir}/${prefix}.tar | awk '{print $1}')
echo "---" >> ${bundle_build_dir}/${prefix}_manifest.txt
echo "${real_md5sum} ${prefix}.tar" >> ${bundle_build_dir}/${prefix}_manifest.txt

## Encrpyt the Bundle
echo "$(date) -- Encrypting and compressing the data bundle"
gpg --batch --passphrase "${pgp_passphrase}" -c ${bundle_build_dir}/${prefix}.tar
rc=$?
if [ ${rc} -ne 0 ]; then
        rm -f ${bundle_build_dir}/aws_bundle_list.txt
        rm -f ${bundle_build_dir}/${prefix}_manifest.txt
	exit 1
fi

## Store checksum of the encrypted bundled
echo "$(date) -- Checksumming the encrypted data bundle"
enc_md5sum=$(md5sum ${bundle_build_dir}/${prefix}.tar.gpg | awk '{print $1}')
echo "${enc_md5sum} ${prefix}.tar.gpg" >> ${bundle_build_dir}/${prefix}_manifest.txt

## Encrpyt a copy of the bundle manifest
echo "$(date) -- Encrypting the file manifeset"
gpg --batch --passphrase "${pgp_passphrase}" -c ${bundle_build_dir}/${prefix}_manifest.txt
rc=$?
if [ ${rc} -ne 0 ]; then
        rm -f ${bundle_build_dir}/aws_bundle_list.txt
        rm -f ${bundle_build_dir}/${prefix}_manifest.txt
	rm -f ${bundle_build_dir}/${prefix}.tar.gpg
        exit 1
fi

## Store local copy of un-eyncrypted manifest
echo "$(date) -- Storing uncrypted manifest locally"
cp ${bundle_build_dir}/${prefix}_manifest.txt ${local_manifest_dir}/
rc=$?
if [ ${rc} -ne 0 ]; then
        rm -f ${bundle_build_dir}/aws_bundle_list.txt
        rm -f ${bundle_build_dir}/${prefix}_manifest.txt
        rm -f ${bundle_build_dir}/${prefix}.tar.gpg
   	rm -f ${bundle_build_dir}/${prefix}_manifest.txt.gpg
        exit 1
fi

## Gather metrics and add to MariaDB Database
echo "$(date) -- Adding bundle metadata to MariaDB database"
bundle_date=$(date +%Y-%m-%d_%H:%M:%S)
bundle_size_bytes=$(stat -c %s ${bundle_build_dir}/${prefix}.tar)
bundle_encrypted_size_bytes=$(stat -c %s ${bundle_build_dir}/${prefix}.tar.gpg)
bundle_manifest_size_bytes=$(stat -c %s ${bundle_build_dir}/${prefix}_manifest.txt)
bundle_manifest_encrypted_size_bytes=$(stat -c %s ${bundle_build_dir}/${prefix}_manifest.txt.gpg)
bundle_file_count=$(wc -l ${bundle_build_dir}/aws_bundle_list.txt | awk '{print $1}')
total_size_to_aws=$((bundle_encrypted_size_bytes+bundle_manifest_encrypted_size_bytes))

mysql -h ${dbhost} --user=$dbuser --password=$dbpassword ${dbname} 2> /dev/null << EOF
INSERT INTO bundle_information (file_path_bundled, bundle_number, bundle_file_name, bundle_file_md5sum, bundle_encrypted_file_md5sum, bundle_file_date_created, bundle_file_size_bytes, bundle_encrypted_size_bytes, bundle_manifest_size_bytes, bundle_manifest_encrypted_size_bytes, bundle_files_contained, bundle_manifest_path, total_bytes_to_aws) VALUES ("${bundle_dir}", "${prefix}", "${prefix}.tar", "$real_md5sum", "$enc_md5sum", "$bundle_date", "$bundle_size_bytes", "$bundle_encrypted_size_bytes", "$bundle_manifest_size_bytes", "$bundle_manifest_encrypted_size_bytes", "$bundle_file_count", "${local_manifest_dir}/${prefix}_manifest.txt", "$total_size_to_aws");
EOF
rc=$?
if [ ${rc} -ne 0 ]; then
        rm -f ${bundle_build_dir}/aws_bundle_list.txt
        rm -f ${bundle_build_dir}/${prefix}_manifest.txt
        rm -f ${bundle_build_dir}/${prefix}.tar.gpg
	rm -f ${bundle_build_dir}/${prefix}_manifest.txt.gpg
	exit 1
fi

## Ship encrypted bundle and manifest to AWS
echo "$(date) -- Shipping encrypted data bundle and encrypted manifest to AWS Deep Glacider"
aws s3 cp ${bundle_build_dir}/${prefix}.tar.gpg s3://${aws_bucket}/ --storage-class DEEP_ARCHIVE
rc=$?
if [ ${rc} -ne 0 ]; then
        rm -f ${bundle_build_dir}/aws_bundle_list.txt
        rm -f ${bundle_build_dir}/${prefix}_manifest.txt
        rm -f ${bundle_build_dir}/${prefix}.tar.gpg
        rm -f ${bundle_build_dir}/${prefix}_manifest.txt.gpg
        exit 1
fi
aws s3 cp ${bundle_build_dir}/${prefix}_manifest.txt.gpg s3://${aws_bucket}/ --storage-class DEEP_ARCHIVE
rc=$?
if [ ${rc} -ne 0 ]; then
        rm -f ${bundle_build_dir}/aws_bundle_list.txt
        rm -f ${bundle_build_dir}/${prefix}_manifest.txt
        rm -f ${bundle_build_dir}/${prefix}.tar.gpg
	echo "Preserving manifest file that failed to upload"
	exit 1
fi

## Remove write access to archived directory
echo "$(date) -- Removing write access to archived directory"
chmod -R u-w ${bundle_dir}
chmod -R g-w ${bundle_dir}
chmod -R a-w ${bundle_dir}

## Clean up
echo "$(date) -- Cleaning up in preparation for completion"
rm -f ${bundle_build_dir}/aws_bundle_list.txt
rm -f ${bundle_build_dir}/${prefix}_manifest.txt
rm -f ${bundle_build_dir}/${prefix}_manifest.txt.gpg
rm -f ${bundle_build_dir}/${prefix}.tar
rm -f ${bundle_build_dir}/${prefix}.tar.gpg
