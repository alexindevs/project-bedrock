def lambda_handler(event, context):
    for record in event['Records']:
        filename = record['s3']['object']['key']
        print(f"Image received: {filename}")
    return {'statusCode': 200}
