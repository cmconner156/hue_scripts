import uuid
from django.db import connection, models, transaction
from search.models import Collection
from desktop.models import Document, Document2
table_names = connection.introspection.table_names()
if Collection._meta.db_table in table_names:
  with transaction.atomic():
    for dashboard in Collection.objects.all():
      if 'collection' in dashboard.properties_dict:
        col_dict = dashboard.properties_dict['collection']
        if not 'uuid' in col_dict:
          _uuid = str(uuid.uuid4())
          col_dict['uuid'] = _uuid
          dashboard.update_properties({'collection': col_dict})
          if dashboard.owner is None:
            from useradmin.models import install_sample_user
            owner = install_sample_user()
          else:
            owner = dashboard.owner
            dashboard_doc = Document2.objects.create(name=dashboard.label, uuid=_uuid, type='search-dashboard', owner=owner, description=dashboard.label, data=dashboard.properties)
            Document.objects.link(dashboard_doc, owner=owner, name=dashboard.label, description=dashboard.label, extra='search-dashboard')
            dashboard.save()

