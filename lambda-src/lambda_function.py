import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def check_if_exists(vpcid,v6cidr):
    client_ec2 = boto3.client('ec2')
    response = client_ec2.describe_subnets(
        Filters=[
            {
                'Name': 'ipv6-cidr-block-association.ipv6-cidr-block',
                'Values': [v6cidr]
            },
            {
                'Name': 'vpc-id',
                'Values': [vpcid]
            },
        ]
    )
    return(len(response['Subnets']))

def create_subnet(az,vpcid,v6cidr):
    client_ec2 = boto3.client('ec2')
    response = client_ec2.create_subnet(
        AvailabilityZone=az,
        Ipv6CidrBlock=v6cidr,
        VpcId=vpcid,
        Ipv6Native=True,
        TagSpecifications=[
            {
                'ResourceType': 'subnet',
                'Tags': [
                    {
                        'Key': 'Name',
                        'Value': 'Priv-v6only-Subnet'
                    },
                ]
            },
        ],

    )
    update_nat64(response['Subnet']['SubnetId'])
    return (response)

def update_nat64(subnet_id):
    client_ec2 = boto3.client('ec2')
    response = client_ec2.modify_subnet_attribute(
        SubnetId=subnet_id,
        EnableDns64={
            'Value': True
        }
    )
    return (0)




def lambda_handler(event, context):

    az = event['az']
    vpcid = event['vpcid']
    v6cidr = event['v6cidr']
    print(event)

    if not (check_if_exists(vpcid,v6cidr)):
        logger.info('Creating subnet...')
        return(create_subnet(az,vpcid,v6cidr)['Subnet']['SubnetId'])

    else:
        logger.info('Already exists')
        return(0)
