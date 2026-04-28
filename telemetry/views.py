from datetime import datetime, timezone

from pymongo import DESCENDING, MongoClient
from pymongo.errors import PyMongoError

from django.conf import settings
from django.http import HttpResponseServerError
from django.urls import reverse
from django.shortcuts import redirect, render

STALE_THRESHOLD_SECONDS = 10


def get_collection():
    mongo_client = MongoClient(
        settings.MONGODB_URI,
        serverSelectionTimeoutMS=1500,
        connectTimeoutMS=1500,
        socketTimeoutMS=1500,
    )
    db = mongo_client[settings.MONGODB_DATABASE]
    return mongo_client, db[settings.MONGODB_COLLECTION]


def dashboard(request):
    try:
        client, collection = get_collection()
        pipeline = [
            {"$sort": {"timestamp_utc": -1}},
            {
                "$group": {
                    "_id": "$vehicle_id",
                    "latest_timestamp": {"$first": "$timestamp_utc"},
                    "latest_temp_celsius": {
                        "$first": {"$ifNull": ["$battery_temperature_c", "$value_celsius"]}
                    },
                    "latest_soc_percent": {"$first": "$battery_soc_percent"},
                }
            },
            {
                "$project": {
                    "_id": 0,
                    "vehicle_id": "$_id",
                    "latest_timestamp": 1,
                    "latest_temp_celsius": 1,
                    "latest_soc_percent": 1,
                }
            },
            {"$sort": {"vehicle_id": 1}},
        ]
        vehicles = list(collection.aggregate(pipeline))
    except PyMongoError as exc:
        return HttpResponseServerError(f"MongoDB error: {exc}")
    finally:
        if "client" in locals():
            client.close()

    now_utc = datetime.now(timezone.utc)
    for vehicle in vehicles:
        latest_timestamp = vehicle.get("latest_timestamp")
        vehicle["is_stale"] = False
        if not latest_timestamp:
            continue
        try:
            seen_at = datetime.fromisoformat(latest_timestamp)
            vehicle["is_stale"] = (now_utc - seen_at).total_seconds() > STALE_THRESHOLD_SECONDS
        except ValueError:
            vehicle["is_stale"] = False

    context = {"vehicles": vehicles}
    return render(request, "telemetry/dashboard.html", context)


def vehicle_detail(request, vehicle_id):
    try:
        client, collection = get_collection()
        readings = list(
            collection.find({"vehicle_id": vehicle_id})
            .sort("timestamp_utc", DESCENDING)
            .limit(100)
        )
    except PyMongoError as exc:
        return HttpResponseServerError(f"MongoDB error: {exc}")
    finally:
        if "client" in locals():
            client.close()

    is_stale = False
    stale_message = None
    if readings:
        latest_timestamp = readings[0].get("timestamp_utc")
        if latest_timestamp:
            try:
                seen_at = datetime.fromisoformat(latest_timestamp)
                seconds_since_last_seen = int((datetime.now(timezone.utc) - seen_at).total_seconds())
                if seconds_since_last_seen > STALE_THRESHOLD_SECONDS:
                    is_stale = True
                    stale_message = (
                        f"Vehicle {vehicle_id} has not reported in {seconds_since_last_seen} seconds. "
                        "Telemetry may be delayed or the EV simulator may be offline."
                    )
            except ValueError:
                pass

    context = {
        "vehicle_id": vehicle_id,
        "readings": readings,
        "is_stale": is_stale,
        "stale_message": stale_message,
    }
    return render(request, "telemetry/vehicle_detail.html", context)


def admin_tools(request):
    if request.method == "POST":
        admin_message = ""
        try:
            client, collection = get_collection()
            result = collection.delete_many({})
            admin_message = f"Deleted {result.deleted_count} telemetry record(s)."
        except PyMongoError as exc:
            admin_message = f"MongoDB error while clearing data: {exc}"
        finally:
            if "client" in locals():
                client.close()
        return redirect(f"{reverse('admin_tools')}?message={admin_message}")

    total_documents = 0
    mongo_error = None
    try:
        client, collection = get_collection()
        total_documents = collection.count_documents({})
    except PyMongoError as exc:
        mongo_error = str(exc)
    finally:
        if "client" in locals():
            client.close()

    context = {
        "total_documents": total_documents,
        "mongo_error": mongo_error,
        "admin_message": request.GET.get("message"),
    }
    return render(request, "telemetry/admin_tools.html", context)
