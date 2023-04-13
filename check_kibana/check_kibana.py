import sys
import json

# check kibana status for v8.x


def check_kibana_migrations_v8(status):
    if "core" in status:
        if "savedObjects" in status["core"]:
            if "summary" in status["core"]["savedObjects"]:
                if "completed migrations" in status["core"]["savedObjects"]["summary"] \
                        and "available" in status["core"]["savedObjects"]["summary"]:
                    sys.exit(0)

    sys.exit(2)


def check_kibana_status_v8(status):
    if "overall" in status:
        if "level" in status["overall"]:
            if status["overall"]["level"] == "available":
                check_kibana_migrations_v8(status)
    sys.exit(1)

# check kibana status for v7.17


def check_kibana_status(status):
    if "overall" in status:
        if "state" in status["overall"]:
            if status["overall"]["state"] == "green":
                check_migration_status(status)
    check_kibana_status_v8(status)


def check_migration_status(status):
    if "statuses" in status:
        for plugin in status["statuses"]:
            if "core:savedObjects" in plugin["id"]:
                if "message" in plugin:
                    if "completed migrations" in plugin["message"] \
                            and "available" in plugin["message"]:
                        sys.exit(0)
    sys.exit(2)


# takes piped in curl output from https://localhost:5601/api/status
# and checks whether or not kibana is online and finished with data migrations (upgrades)
try:
    response = json.load(sys.stdin)
except ValueError:
    sys.exit(4)

if "status" in response:
    status = response["status"]
    check_kibana_status(status)

sys.exit(3)
