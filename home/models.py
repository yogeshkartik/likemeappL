# from django.db import models

# # Create your models here.
# from django.contrib.auth.models import AbstractUser

# class CustomUser(AbstractUser):
#     # Add the new field here
#     nickname = models.CharField(max_length=100)


from django.contrib.gis.db import models
from django.contrib.gis.geos import Point


import uuid



def user_directory_path(instance, filename):
    # file will be uploaded to MEDIA_ROOT/user_<id>/<filename>
    return 'user_{0}/{1}'.format(instance.user_name, filename)


def generate_filename(instance, filename):
    ext = filename.split('.')[-1]
    filename = f"{uuid.uuid4()}.{ext}"
    # return f"user/{instance.user_name}/uploads/{filename}"
    return f"user/{instance.username}/uploads/{filename}"


class Client(models.Model):
    username = models.CharField(max_length=100)
    location = models.PointField(geography=True, default=Point(0.0, 0.0))
    file_name = models.CharField(blank=True, max_length=255)
    file = models.FileField(blank=True, upload_to= generate_filename)
    upload_date = models.DateTimeField(null=True, auto_now_add=True)
    


# class UploadedFile(models.Model):
    # file = models.FileField(upload_to="userimages/")
    # user_name = models.CharField(null=True,max_length=255)
    # file_name = models.CharField(max_length=255)
    # file = models.FileField(upload_to= generate_filename)
    # upload_date = models.DateTimeField(auto_now_add=True)
    # file_size = models.IntegerField()


