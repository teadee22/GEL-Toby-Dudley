import boto3
import os
from PIL import Image
import logging

s3 = boto3.resource('s3')
s3_client = boto3.client('s3')

S3_BUCKET_A = os.environ.get('S3_BUCKET_A', 'gel-bucket-a')
S3_BUCKET_B = os.environ.get('S3_BUCKET_B', 'gel-bucket-b')

def handler(event, context):

    key = event['Records'][0]['s3']['object']['key']
    print(f"Detected file uploaded to {S3_BUCKET_A} with name {key}")

    download_file_from_s3(key, S3_BUCKET_A)
    print(f"Downloaded {key}")

    strip_exif("/tmp/tmp.jpg")
    print(f"Stripped exif data from {key}")

    upload_file_to_s3('/tmp/exif_stripped.jpg', S3_BUCKET_B, key)
    print(f"Uploaded {key} to {S3_BUCKET_B}")

    return 200

def download_file_from_s3(key: str, bucket: str):
    try:
        s3.Bucket(S3_BUCKET_A).download_file(key, "/tmp/tmp.jpg")
    except NameError as e:
        if e.response['Error']['Code'] == "404":
            logging.error(f"The object {key} does not exist.")
        else:
            raise

def upload_file_to_s3(file_name: str, bucket: str, key: str):
    try:
        response = s3_client.upload_file(file_name, S3_BUCKET_B, key)
    except NameError as e:
        raise logging.error(e)

def strip_exif(image: str):
    try:
        image = Image.open(image)
        data = list(image.getdata())
        image_without_exif = Image.new(image.mode, image.size)
        image_without_exif.putdata(data)

        image_without_exif.save('/tmp/exif_stripped.jpg')
    except Exception as e:
        raise logging.error(e)