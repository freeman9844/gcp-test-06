FROM golang:1.23-alpine AS builder

WORKDIR /app

COPY go.mod ./
COPY main.go ./

RUN go build -o main .

FROM alpine:3.19

WORKDIR /app
COPY --from=builder /app/main .

EXPOSE 8080
CMD ["./main"]
