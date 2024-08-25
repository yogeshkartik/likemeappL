from django import forms
from .models import ClientLocPost, PostImage

class PostForm(forms.ModelForm):
    class Meta:
        model = ClientLocPost
        fields = ['title', 'content']

class ImageForm(forms.ModelForm):
    class Meta:
        model = PostImage
        fields = ['image']
