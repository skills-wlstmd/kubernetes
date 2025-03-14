FROM node:18

WORKDIR /usr/src/app

COPY package.json ./

RUN apt-get update && apt-get install -y iputils-ping && npm install

COPY . .

EXPOSE 8080

CMD ["node", "app.js"]