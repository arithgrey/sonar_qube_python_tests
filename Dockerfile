# Define las imágenes base y argumentos
ARG BUILD_SONAR=sonarsource/sonar-scanner-cli:4.3
ARG BUILD_IMAGE=python:3.9.4

#############################################################################################
###                Stage de construcción inicial con instalación de dependencias          ###
#############################################################################################

# Usa una imagen de Python como base para la construcción inicial
FROM ${BUILD_IMAGE} as base-build

# Establece el directorio de trabajo dentro del contenedor
WORKDIR /src

# Copia los archivos de requisitos y de código fuente para la construcción
COPY requirements.txt /src/
RUN pip install --upgrade pip && pip install -r requirements.txt


COPY src /src

#############################################################################################
###                Stage donde Docker está ejecutando las pruebas                         ###
#############################################################################################

# Usa la imagen construida con las dependencias instaladas para las pruebas
FROM base-build as tests

RUN pip install pytest pytest-cov

RUN pytest \
  -p no:cacheprovider \
  -vv -o junit_family=xunit1 \
  --cov-report xml:cov.xml \
  --cov-report term-missing \
  --junitxml=results.xml \
  --cov=.

RUN ls -l

#############################################################################################
###                Stage donde Docker está ejecutando el análisis de SonarQube            ###
#############################################################################################

# Usa la imagen del escáner de SonarQube como base
FROM ${BUILD_SONAR} AS sonar

WORKDIR /opt/findep

# Paso a Root para que tenga acceso de escritura
USER root

RUN mkdir -p /opt/findep/.scannerwork \
  && chown -R scanner-cli:scanner-cli /opt/findep/

# Copia los archivos de código fuente y configuración de SonarQube
COPY sonar-project.properties /opt/findep

# Copia los archivos de informes generados en la etapa de pruebas
COPY --from=tests /src /opt/findep/

RUN sonar-scanner -X -Dproject.settings=/opt/findep/sonar-project.properties

#############################################################################################
###               Etapa final                                                             ###
#############################################################################################

# Usa la imagen construida con las dependencias instaladas como base final
FROM base-build as base

WORKDIR /src

COPY --from=sonar /opt/findep/sonar-project.properties /src

# Configuración de usuario y permisos
USER root
RUN chmod u+x /src/gunicorn.sh

RUN useradd -ms /bin/sh admin
USER admin

EXPOSE 8080

ENTRYPOINT ["sh", "/src/gunicorn.sh"]
