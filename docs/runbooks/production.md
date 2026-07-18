# Production

1. Set `BEDD_BUS_URL` to the in-cluster HTTP bus service
2. Mount a host-specific tinder JSON via `BEDD_TINDER`
3. Set unique `BEDD_CONSUMER_NAME` per replica
4. Probe `/healthz` on `BEDD_ADMIN_PORT`
5. Configure `BEDD_DLQ_STREAM` for your bus topology
