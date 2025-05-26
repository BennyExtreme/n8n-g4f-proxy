FROM node:18-alpine AS builder

WORKDIR /proxy

COPY package*.json ./

RUN npm install

COPY . .

RUN npm install && npm run build

FROM node:18-alpine

WORKDIR /proxy

COPY --from=builder /proxy ./

EXPOSE 3000

CMD ["npm", "run", "start"]
