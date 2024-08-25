# from django.db import models

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
    return f"user/{instance.username}/uploads/post/{filename}"



"""
pehle ye krte hain ki user agar koi image nahi upload kiya to uska
kuch v post display nahi hoga
mtlb avi k hisab se bas latest post hi display hoga
.
.
baad me agar uska post page banane ka dekha jayega
"""
class ClientLocPost(models.Model):
    username = models.CharField(max_length=100)
    location = models.PointField(geography=True, default=Point(0.0, 0.0))
    title = models.CharField(max_length=255)
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.title
    # file_name = models.CharField(blank=True, max_length=255)
    # file = models.FileField(blank=True, upload_to= generate_filename)
    # upload_date = models.DateTimeField(null=True, auto_now_add=True)
    
# class Post(models.Model):
#     title = models.CharField(max_length=255)
#     content = models.TextField()
#     created_at = models.DateTimeField(auto_now_add=True)

#     def __str__(self):
#         return self.title

class PostImage(models.Model):
    post = models.ForeignKey(ClientLocPost, on_delete=models.CASCADE, related_name='images')
    username = models.CharField(max_length=100)
    image = models.ImageField(upload_to=generate_filename)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.post.title} Image"


