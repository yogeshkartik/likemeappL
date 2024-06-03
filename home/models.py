# from django.db import models

# # Create your models here.
# from django.contrib.auth.models import AbstractUser

# class CustomUser(AbstractUser):
#     # Add the new field here
#     nickname = models.CharField(max_length=100)


from django.contrib.gis.db import models
from django.contrib.gis.geos import Point
class Client(models.Model):
    username = models.CharField(max_length=100)
    location = models.PointField(geography=True, default=Point(0.0, 0.0))
    