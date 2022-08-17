# GEL task - Toby Dudley

## Configuration
- choose aws_region and set it in `variables.tf`

## Create infrastructure
- `terraform apply`

## Usage
- upload an image with exif info e.g. `aws s3 cp test.jpg s3://gel-bucket-a/test.jpg`
- The lambda will process the image to remove exif info and another image with the same name will be found in the second bucket without exif data `s3://gel-bucket-b/test.jpg`