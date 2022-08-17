import boto3
import os
from PIL import Image

batch = boto3.client('batch')
s3 = boto3.client('s3')
ssm = boto3.client('ssm')

S3_BUCKET = os.environ.get('S3_BUCKET_A', 'gel_bucket_a')
S3_BUCKET = os.environ.get('S3_BUCKET_B', 'gel_bucket_b')

def handler(event, context):

    print(event)

    # image = Image.open('test.jpg')

    # # next 3 lines strip exif
    # data = list(image.getdata())
    # image_without_exif = Image.new(image.mode, image.size)
    # image_without_exif.putdata(data)

    # image_without_exif.save('image_file_without_exif.jpeg')

