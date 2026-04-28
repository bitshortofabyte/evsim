#!/bin/bash

# ===================== CONFIG =====================
MONGO_CONTAINER="mongodb"
MQTT_CONTAINER="mosquitto"

MONGO_PORT=27017
MQTT_PORT=1883

# Named volumes (persistent data)
MONGO_VOLUME="mongodb_data"
MQTT_VOLUME="mosquitto_data"
# ================================================

case "$1" in
    start)
        echo "🚀 Starting MongoDB and Mosquitto..."

        # Create volumes if they don't exist
        docker volume create $MONGO_VOLUME >/dev/null 2>&1
        docker volume create $MQTT_VOLUME >/dev/null 2>&1

        # Start MongoDB
        docker run -d \
            --name $MONGO_CONTAINER \
            -p $MONGO_PORT:27017 \
            -v $MONGO_VOLUME:/data/db \
            --restart unless-stopped \
            mongo:latest

        # Start Mosquitto
        docker run -d \
            --name $MQTT_CONTAINER \
            -p $MQTT_PORT:1883 \
            -v $MQTT_VOLUME:/mosquitto/data \
            --restart unless-stopped \
            eclipse-mosquitto

        echo "✅ Both services started!"
        echo "   MongoDB  → localhost:$MONGO_PORT"
        echo "   Mosquitto → localhost:$MQTT_PORT"
        ;;

    stop)
        echo "🛑 Stopping MongoDB and Mosquitto..."
        docker stop $MONGO_CONTAINER $MQTT_CONTAINER 2>/dev/null
        echo "✅ Services stopped."
        ;;

    restart)
        $0 stop
        sleep 2
        $0 start
        ;;

    status)
        echo "📊 Container Status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$MONGO_CONTAINER|$MQTT_CONTAINER|NAMES"
        ;;

    logs)
        echo "=== MongoDB Logs ==="
        docker logs $MONGO_CONTAINER --tail=50
        echo -e "\n=== Mosquitto Logs ==="
        docker logs $MQTT_CONTAINER --tail=50
        ;;

    rm)
        echo "🗑️  Removing containers and stopping them..."
        docker rm -f $MONGO_CONTAINER $MQTT_CONTAINER 2>/dev/null
        echo "✅ Containers removed."
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|logs|rm}"
        echo ""
        echo "Examples:"
        echo "  $0 start     # Start both services"
        echo "  $0 stop      # Stop both services"
        echo "  $0 restart   # Restart both"
        echo "  $0 status    # Show running status"
        echo "  $0 logs      # Show recent logs"
        echo "  $0 rm        # Remove containers"
        exit 1
        ;;
esac