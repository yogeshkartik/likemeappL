from django.db import models

# Create your models here.


class users(models.Model):
	name = models.CharField(max_length=200)
	username = models.CharField(max_length=200)
	userpswd = models.CharField(max_length=200)
	userlat = models.IntegerField()
	userlong = models.IntegerField()

# 	def __str__(self):
# 		return self.name

