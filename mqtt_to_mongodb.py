import json
import signal
import sys

import paho.mqtt.client as mqtt
from pymongo import MongoClient
from pymongo.errors import PyMongoError


BROKER_HOST = "localhost"
BROKER_PORT = 1883
MQTT_TOPIC = "ev/sensors/telemetry"
MQTT_CLIENT_ID = "ev-mongodb-ingestor"

MONGODB_URI = "mongodb://localhost:27017"
MONGODB_DATABASE = "ev_telemetry"
MONGODB_COLLECTION = "sensor_readings"


mongo_client = MongoClient(MONGODB_URI)
collection = mongo_client[MONGODB_DATABASE][MONGODB_COLLECTION]


def on_connect(client: mqtt.Client, userdata, flags, reason_code, properties=None) -> None:
    if reason_code == 0:
        print(f"Connected to MQTT broker at {BROKER_HOST}:{BROKER_PORT}")
        client.subscribe(MQTT_TOPIC, qos=1)
        print(f"Subscribed to topic: {MQTT_TOPIC}")
    else:
        print(f"MQTT connection failed with code {reason_code}")


def on_message(client: mqtt.Client, userdata, msg: mqtt.MQTTMessage) -> None:
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
        result = collection.insert_one(payload)
        print(f"Saved reading to MongoDB (id={result.inserted_id})")
    except json.JSONDecodeError as exc:
        print(f"Invalid JSON payload: {exc}")
    except PyMongoError as exc:
        print(f"MongoDB insert failed: {exc}")


def main() -> None:
    running = True

    def shutdown_handler(signum, frame) -> None:
        nonlocal running
        print("\nStopping MongoDB ingestor...")
        running = False

    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)

    client = mqtt.Client(client_id=MQTT_CLIENT_ID, protocol=mqtt.MQTTv5)
    client.on_connect = on_connect
    client.on_message = on_message

    client.connect(BROKER_HOST, BROKER_PORT, keepalive=60)
    client.loop_start()

    try:
        while running:
            signal.pause()
    finally:
        client.loop_stop()
        client.disconnect()
        mongo_client.close()
        print("Disconnected from MQTT and MongoDB")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Fatal error: {exc}")
        sys.exit(1)
