import base64
import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("processor", ROOT / "lambda/handler.py")
handler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handler)


def event():
    return dict(event_id="e1",rfid="r1",product_id="LAPTOP",warehouse_id="A",
                movement="entrada",timestamp="2026-10-13T10:00:00-06:00")


def record():
    return {"eventID":"event","kinesis":{"sequenceNumber":"123",
            "data":base64.b64encode(json.dumps(event()).encode()).decode()}}


class ProcessorTests(unittest.TestCase):
    def test_timestamp_is_utc_and_matches_clickhouse_column(self):
        row = handler.normalize(event())
        self.assertEqual(row["occurred_at"], "2026-10-13 16:00:00.000000")
        self.assertNotIn("timestamp",row)

    def test_naive_timestamp_and_long_identifier_rejected(self):
        for changes in ({"timestamp":"2026-10-13T10:00:00"},{"rfid":"x"*129}):
            row=event();row.update(changes)
            with self.assertRaises(ValueError): handler.normalize(row)

    @patch.dict(os.environ,CLICKHOUSE_URL="http://10.50.10.5:8123")
    def test_values_are_json_not_sql_and_multiline_payload_is_valid(self):
        row=event();row["product_id"]="x'); DROP TABLE raw_events; --"
        rows=[handler.normalize(row),handler.normalize(event())]
        response=Mock();response.read.return_value=b""
        context=Mock();context.__enter__=Mock(return_value=response);context.__exit__=Mock(return_value=False)
        with patch.object(handler.urllib.request,"urlopen",return_value=context) as http:
            handler.insert_batch(rows,Mock())
        req=http.call_args.args[0]
        self.assertNotIn("DROP",req.full_url)
        self.assertEqual([json.loads(line) for line in req.data.splitlines()],rows)
        self.assertEqual(req.get_header("X-clickhouse-user"),"ingestor")

    def test_http_failure_returns_batch_for_retry(self):
        with patch.object(handler,"insert_batch",side_effect=HTTPError("url",503,"Unavailable",None,None)):
            with self.assertLogs(handler.log,level="ERROR"):
                result=handler.lambda_handler({"Records":[record()]},Mock())
        self.assertEqual(result,{"batchItemFailures":[{"itemIdentifier":"123"}]})

    def test_invalid_event_does_not_reach_clickhouse(self):
        bad=record();bad["kinesis"]["data"]="e30="
        with patch.object(handler,"insert_batch") as insert:
            with self.assertLogs(handler.log,level="ERROR"):
                result=handler.lambda_handler({"Records":[bad]},Mock())
        insert.assert_not_called()
        self.assertEqual(result,{"batchItemFailures":[]})

    def test_success_acknowledges_batch(self):
        with patch.object(handler,"insert_batch") as insert:
            result=handler.lambda_handler({"Records":[record()]},Mock())
        insert.assert_called_once()
        self.assertEqual(result,{"batchItemFailures":[]})


if __name__ == "__main__": unittest.main()
