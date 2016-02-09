from django.contrib.auth.models import User
usernames = ['cconner@test.com', 'tuser2']
User.objects.filter(username__in=usernames).delete()
