#!/bin/bash
#Clean up old history to keep DB from growing too large

/opt/cloudera/hue_scripts/script_runner hue_desktop_document_cleanup --keep-days 30