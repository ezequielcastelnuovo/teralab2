FROM public.ecr.aws/docker/library/php:7.2-apache

COPY . /var/www/html
COPY ./apache/default-site.conf /etc/apache2/sites-available/default-site.conf

WORKDIR /var/www/html

#Esto es del dockerfile de lisandro, necesario para poder tirar los apt update y upgrade`3
RUN sed -i -e 's/deb.debian.org/archive.debian.org/g' \
           -e 's|security.debian.org|archive.debian.org/|g' \
           -e '/stretch-updates/d' /etc/apt/sources.list

RUN apt-get update && apt-get upgrade -y
RUN apt-get update && apt-get install wget git -y

RUN make

#Esto es del dockerfile de joaco
RUN ln -s /etc/apache2/sites-available/default-site.conf /etc/apache2/sites-enabled/default-site.conf

#Esto es del dockerfile de lisandro, si no lo uso (osea, si no se desactiva el 000-default) la app te tira Forbidden.
RUN a2dissite 000-default.conf && \
    a2ensite default-site.conf

RUN docker-php-ext-install pdo pdo_mysql &&\
	docker-php-ext-configure pdo &&\
	docker-php-ext-configure pdo_mysql

RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf &&\
	chown -R www-data:www-data /var/www/html/ &&\
	# sed -i 's/localhost/database/g' ./config/db-connection.php &&\
	mkdir /var/log/apache2/example-app/ &&\
	chown -R www-data:www-data /var/log/apache2/example-app/ &&\
	a2enmod rewrite &&\
	service apache2 restart

##Remove unnecesary files
RUN rm -r sql/ apache/ &&\
	rm Dockerfile Makefile README.md

EXPOSE 80