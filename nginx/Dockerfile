FROM nginx:1.27.0

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d

# COPY ../test.txt /app/media
# COPY ../media /app/media

# Set the appropriate ownership and permissions
# RUN chown -R www-data:www-data /app/staticfiles /app/media
# RUN chmod -R 755 /app/staticfiles /app/media

# Expose port 80
EXPOSE 80

# Run Nginx
CMD ["nginx", "-g", "daemon off;"]