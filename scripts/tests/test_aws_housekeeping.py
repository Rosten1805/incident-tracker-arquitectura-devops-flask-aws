import argparse
import json
from unittest.mock import patch

import boto3
import pytest
from moto import mock_aws

from aws_housekeeping import (
    cmd_backup,
    cmd_stop_idle,
    fetch_tasks_snapshot,
    list_project_instances,
    upload_backup,
)


def _launch_instance(ec2_client, *, name: str, project: str | None, state: str = "running"):
    reservation = ec2_client.run_instances(
        ImageId="ami-12345678",
        MinCount=1,
        MaxCount=1,
        InstanceType="t3.micro",
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": [
                    {"Key": "Name", "Value": name},
                    *([{"Key": "Project", "Value": project}] if project else []),
                ],
            }
        ],
    )
    instance_id = reservation["Instances"][0]["InstanceId"]
    if state == "stopped":
        ec2_client.stop_instances(InstanceIds=[instance_id])
    return instance_id


@mock_aws
def test_list_project_instances_filtra_por_tag():
    ec2 = boto3.client("ec2", region_name="eu-west-1")
    _launch_instance(ec2, name="task-tracker-app-server", project="task-tracker")
    _launch_instance(ec2, name="otro-proyecto", project="otro-proyecto")

    instances = list_project_instances(ec2, project="task-tracker")

    assert len(instances) == 1
    assert instances[0]["name"] == "task-tracker-app-server"
    assert instances[0]["state"] == "running"
    assert instances[0]["running_hours"] >= 0


@mock_aws
def test_upload_backup_sube_el_contenido_correcto():
    s3 = boto3.client("s3", region_name="eu-west-1")
    s3.create_bucket(
        Bucket="mi-bucket-backups",
        CreateBucketConfiguration={"LocationConstraint": "eu-west-1"},
    )

    snapshot = {"backed_up_at": "2026-01-01T00:00:00+00:00", "source": "http://alb/tasks", "tasks": [{"id": 1}]}
    key = upload_backup(s3, "mi-bucket-backups", snapshot)

    assert key.startswith("backups/tasks-") and key.endswith(".json")
    body = s3.get_object(Bucket="mi-bucket-backups", Key=key)["Body"].read()
    assert json.loads(body) == snapshot


def test_fetch_tasks_snapshot_llama_a_la_api_de_la_app():
    tasks_json = json.dumps([{"id": 1, "title": "demo"}]).encode("utf-8")

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def read(self):
            return tasks_json

    with patch("aws_housekeeping.urllib.request.urlopen", return_value=FakeResponse()) as mocked:
        snapshot = fetch_tasks_snapshot("task-tracker-alb-123.eu-west-1.elb.amazonaws.com")

    mocked.assert_called_once()
    called_url = mocked.call_args.args[0]
    assert called_url == "http://task-tracker-alb-123.eu-west-1.elb.amazonaws.com/tasks"
    assert snapshot["tasks"] == [{"id": 1, "title": "demo"}]
    assert "backed_up_at" in snapshot


@mock_aws
def test_stop_idle_sin_confirm_no_para_nada():
    ec2 = boto3.client("ec2", region_name="eu-west-1")
    instance_id = _launch_instance(ec2, name="task-tracker-app-server", project="task-tracker")

    args = argparse.Namespace(region="eu-west-1", project="task-tracker", max_hours=0, confirm=False)
    cmd_stop_idle(args)

    state = ec2.describe_instances(InstanceIds=[instance_id])["Reservations"][0]["Instances"][0]["State"]["Name"]
    assert state == "running"


@mock_aws
def test_stop_idle_con_confirm_para_la_instancia():
    ec2 = boto3.client("ec2", region_name="eu-west-1")
    instance_id = _launch_instance(ec2, name="task-tracker-app-server", project="task-tracker")

    args = argparse.Namespace(region="eu-west-1", project="task-tracker", max_hours=0, confirm=True)
    cmd_stop_idle(args)

    state = ec2.describe_instances(InstanceIds=[instance_id])["Reservations"][0]["Instances"][0]["State"]["Name"]
    assert state in ("stopping", "stopped")
