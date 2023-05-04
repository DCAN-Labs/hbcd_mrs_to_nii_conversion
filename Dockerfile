#Python base image
FROM python:3.9.16-slim-bullseye

# Installation for dcmtk
RUN apt update -y && apt upgrade -y
RUN apt-get -y install curl
RUN apt install dcmtk -y

# Installation for conda
#RUN apt install gnupg -y
#RUN curl https://repo.anaconda.com/pkgs/misc/gpgkeys/anaconda.asc | gpg --dearmor > conda.gpg
#RUN install -o root -g root -m 644 conda.gpg /usr/share/keyrings/conda-archive-keyring.gpg
#RUN gpg --keyring /usr/share/keyrings/conda-archive-keyring.gpg --no-default-keyring --fingerprint 34161F5BF5EB1D4BFBBB8F0A8AEB4F8B29D82806
#RUN echo "deb [arch=amd64 signed-by=/usr/share/keyrings/conda-archive-keyring.gpg] https://repo.anaconda.com/pkgs/misc/debrepo/conda stable main" > /etc/apt/sources.list.d/conda.list
#RUN apt update
#RUN apt install conda -y

#NEW LINE
#ENV PATH=/opt/conda/bin:$PATH
#RUN source /opt/conda/etc/profile.d/conda.sh

RUN mkdir /code
#COPY environment.yml /code/environment.yml
#RUN conda env create -f /code/environment.yml
#SHELL ["conda", "run", "-n", "myenv", "/bin/bash", "-c"] #THIS MIGHT BE NECESSARY
#RUN echo "source activate myenv" > ~/.bashrc 
#RUN conda init bash --system
RUN pip install spec2nii==0.6.8

#NEW LINE
#SHELL ["conda", "run", "-n", "myenv", "/bin/bash", "-c"]

# Install FSL-MRS (not needed anymore, but keeping here for reference)
#RUN conda install -c conda-forge -c defaults -c https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/public/ fsl_mrs


RUN apt install -y unar

COPY spec2nii_HBCD_batch.sh /code/run.sh

#ENTRYPOINT ["bash", "/opt/conda/etc/profile.d/conda.sh", "activate", "&&", "bash", "/code/run.sh"]
ENTRYPOINT ["bash", "/code/run.sh"]

RUN chmod 555 -R /code
