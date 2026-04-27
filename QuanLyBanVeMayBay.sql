Create database QuanLyBanVeMayBay
ON PRIMARY (
    NAME = QLBanVe_Data,
    FILENAME = 'D:\File học tập\SQL Server\Đồ án CN_Net\QLBanVe_Data.mdf',
    SIZE = 50MB,
    MAXSIZE = 500MB,
    FILEGROWTH = 10MB
)
LOG ON (
    NAME = QLBanVe_Log,
    FILENAME = 'D:\File học tập\SQL Server\Đồ án CN_Net\QLBanVe_Log.ldf',
    SIZE = 30MB,
    MAXSIZE = 200MB,
    FILEGROWTH = 10MB
);
GO
Use QuanLyBanVeMayBay
Go

--Bảng role --
CREATE TABLE roles (
    role_id INT IDENTITY(1,1) PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL
);
--Bảng employees --
CREATE TABLE employees (
    employee_id INT IDENTITY(1,1) PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role_id INT NOT NULL,
    status VARCHAR(20) DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','INACTIVE')),
    created_at DATETIME DEFAULT GETDATE(),

    CONSTRAINT fk_employee_role
        FOREIGN KEY (role_id) REFERENCES roles(role_id)
);
--Bảng aircrafts --
CREATE TABLE aircrafts (
    aircraft_id INT IDENTITY(1,1) PRIMARY KEY,
    aircraft_code VARCHAR(20) UNIQUE NOT NULL,
    aircraft_type VARCHAR(100) NOT NULL,
    total_seats INT NOT NULL CHECK (total_seats > 0),
    manufacturer VARCHAR(100)
);
--Bảng seat --
CREATE TABLE seats (
    seat_id INT IDENTITY(1,1) PRIMARY KEY,
    aircraft_id INT NOT NULL,
    seat_number VARCHAR(5) NOT NULL,
    seat_class VARCHAR(20)
        CHECK (seat_class IN ('ECONOMY','BUSINESS','FIRST')),
    seat_status VARCHAR(20) DEFAULT 'AVAILABLE'
        CHECK (seat_status IN ('AVAILABLE','SELECTED','BOOKED')),

    CONSTRAINT fk_seat_aircraft
        FOREIGN KEY (aircraft_id) REFERENCES aircrafts(aircraft_id),

    CONSTRAINT unique_seat_per_aircraft
        UNIQUE (aircraft_id, seat_number)
);
--Bảng airports --
CREATE TABLE airports (
    airport_id INT IDENTITY(1,1) PRIMARY KEY,
    airport_code VARCHAR(10) UNIQUE NOT NULL,
    airport_name VARCHAR(150) NOT NULL,
    city VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL
);
--Bảng flights --
CREATE TABLE flights (
    flight_id INT IDENTITY(1,1) PRIMARY KEY,
    flight_number VARCHAR(20) NOT NULL,
    departure_time DATETIME NOT NULL,
    arrival_time DATETIME NOT NULL,
    departure_airport INT NOT NULL,
    arrival_airport INT NOT NULL,
    aircraft_id INT NOT NULL,
    airline VARCHAR(100) NOT NULL,
    flight_status VARCHAR(20) DEFAULT 'AVAILABLE'
        CHECK (flight_status IN ('AVAILABLE','FULL','DEPARTED','DELAYED','CANCELLED')),

    CONSTRAINT fk_departure_airport
        FOREIGN KEY (departure_airport) REFERENCES airports(airport_id),

    CONSTRAINT fk_arrival_airport
        FOREIGN KEY (arrival_airport) REFERENCES airports(airport_id),

    CONSTRAINT fk_flight_aircraft
        FOREIGN KEY (aircraft_id) REFERENCES aircrafts(aircraft_id),

    CONSTRAINT chk_time CHECK (arrival_time > departure_time)
);
--Bảng customers --
CREATE TABLE customers (
    customer_id INT IDENTITY(1,1) PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    id_number VARCHAR(20) NOT NULL UNIQUE,
    phone VARCHAR(20),
    email VARCHAR(100)
);
--Bảng tickets --
CREATE TABLE tickets (
    ticket_id INT IDENTITY(1,1) PRIMARY KEY,
    flight_id INT NOT NULL,
    customer_id INT NOT NULL,
    seat_id INT NOT NULL,
    price DECIMAL(12,2) NOT NULL CHECK (price >= 0),
    tax DECIMAL(12,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'UNPAID'
        CHECK (status IN ('UNPAID','PAID','CANCELLED','REFUNDED')),
    booking_time DATETIME DEFAULT GETDATE(),

    CONSTRAINT fk_ticket_flight
        FOREIGN KEY (flight_id) REFERENCES flights(flight_id),

    CONSTRAINT fk_ticket_customer
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id),

    CONSTRAINT fk_ticket_seat
        FOREIGN KEY (seat_id) REFERENCES seats(seat_id),

    CONSTRAINT unique_seat_booking
        UNIQUE (flight_id, seat_id)
);
--Bảng payments --
CREATE TABLE payments (
    payment_id INT IDENTITY(1,1) PRIMARY KEY,
    ticket_id INT NOT NULL,
    payment_method VARCHAR(30)
        CHECK (payment_method IN ('BANK_TRANSFER','EWALLET','LOCAL_CARD')),
    payment_status VARCHAR(20)
        CHECK (payment_status IN ('SUCCESS','FAILED')),
    payment_time DATETIME DEFAULT GETDATE(),

    CONSTRAINT fk_payment_ticket
        FOREIGN KEY (ticket_id) REFERENCES tickets(ticket_id)
);

--TRIGGER--
--Trigger đặt vé->ghế=BOOKED--
CREATE TRIGGER trg_after_ticket_insert
ON tickets
AFTER INSERT
AS
BEGIN
    UPDATE seats
    SET seat_status = 'BOOKED'
    FROM seats s
    JOIN inserted i ON s.seat_id = i.seat_id;
END;
GO

--Trigger hủy vé->available--
CREATE TRIGGER trg_after_ticket_cancel
ON tickets
AFTER UPDATE
AS
BEGIN
    UPDATE seats
    SET seat_status = 'AVAILABLE'
    FROM seats s
    JOIN inserted i ON s.seat_id = i.seat_id
    JOIN deleted d ON i.ticket_id = d.ticket_id
    WHERE i.status = 'CANCELLED';
END;
GO

--Trigger thanh toán thành công->vé=paid--
CREATE TRIGGER trg_payment_success
ON payments
AFTER INSERT
AS
BEGIN
    UPDATE tickets
    SET status = 'PAID'
    FROM tickets t
    JOIN inserted i ON t.ticket_id = i.ticket_id
    WHERE i.payment_status = 'SUCCESS';
END;
GO

--Trigger kiểm tra full chuyến bay--
CREATE TRIGGER trg_check_flight_full
ON tickets
AFTER INSERT
AS
BEGIN
    UPDATE flights
    SET flight_status = 'FULL'
    WHERE flight_id IN (
        SELECT f.flight_id
        FROM flights f
        JOIN aircrafts a ON f.aircraft_id = a.aircraft_id
        WHERE (
            SELECT COUNT(*)
            FROM tickets t
            WHERE t.flight_id = f.flight_id
            AND t.status <> 'CANCELLED'
        ) >= a.total_seats
    );
END;
GO

--Trigger không cho đặt vé nếu flight không hợp lệ--
CREATE TRIGGER trg_before_ticket_insert
ON tickets
INSTEAD OF INSERT
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN flights f ON i.flight_id = f.flight_id
        WHERE f.flight_status IN ('CANCELLED','DEPARTED')
    )
    BEGIN
        RAISERROR ('Cannot book ticket for this flight',16,1);
        RETURN;
    END

    INSERT INTO tickets (flight_id, customer_id, seat_id, price, tax, status)
    SELECT flight_id, customer_id, seat_id, price, tax, status
    FROM inserted;
END;
GO

--Trigger không cho hoàn vé nếu chưa paid--
CREATE TRIGGER trg_before_refund
ON tickets
AFTER UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON i.ticket_id = d.ticket_id
        WHERE i.status = 'REFUNDED' AND d.status <> 'PAID'
    )
    BEGIN
        RAISERROR ('Only paid tickets can be refunded',16,1);
        ROLLBACK TRANSACTION;
    END
END;
GO

--INDEX--
CREATE INDEX idx_flight_search
ON flights(departure_airport, arrival_airport, departure_time);

CREATE INDEX idx_ticket_customer
ON tickets(customer_id);

CREATE INDEX idx_ticket_flight
ON tickets(flight_id);

--INSERT DỮ LIỆU--
--ROLES--
INSERT INTO roles (role_name)
VALUES 
('Admin'),
('Staff'),
('Manager');
GO

--EMPLOYEES--
INSERT INTO employees (username, password_hash, full_name, role_id)
VALUES
('admin1', '123456', 'Nguyen Van A', 1),
('staff1', '123456', 'Tran Van B', 2),
('manager1', '123456', 'Le Van C', 3);
GO

--AIRPORTS--
INSERT INTO airports (airport_code, airport_name, city, country)
VALUES
('SGN', 'Tan Son Nhat', 'Ho Chi Minh', 'Vietnam'),
('HAN', 'Noi Bai', 'Ha Noi', 'Vietnam'),
('DAD', 'Da Nang', 'Da Nang', 'Vietnam');
GO

--AIRCRAFT--
INSERT INTO aircrafts (aircraft_code, aircraft_type, total_seats, manufacturer)
VALUES
('VN-A123', 'Airbus A320', 180, 'Airbus'),
('VN-A456', 'Boeing 737', 160, 'Boeing');
GO

--SEATS--
-- Máy bay 1
-- Aircraft 1
DECLARE @i INT = 1;
WHILE @i <= 50
BEGIN
    INSERT INTO seats (aircraft_id, seat_number, seat_class)
    VALUES (
        1,
        'S' + CAST(@i AS VARCHAR),
        CASE 
            WHEN @i <= 5 THEN 'FIRST'
            WHEN @i <= 15 THEN 'BUSINESS'
            ELSE 'ECONOMY'
        END
    );
    SET @i = @i + 1;
END;
GO

-- Aircraft 2
DECLARE @i INT = 1;
WHILE @i <= 50
BEGIN
    INSERT INTO seats (aircraft_id, seat_number, seat_class)
    VALUES (
        2,
        'S' + CAST(@i AS VARCHAR),
        CASE 
            WHEN @i <= 5 THEN 'FIRST'
            WHEN @i <= 15 THEN 'BUSINESS'
            ELSE 'ECONOMY'
        END
    );
    SET @i = @i + 1;
END;
GO

--FLIGHTS--
INSERT INTO flights (
    flight_number, departure_time, arrival_time,
    departure_airport, arrival_airport, aircraft_id, airline
)
VALUES
('VN001', '2026-04-01 08:00', '2026-04-01 10:00', 1, 2, 1, 'Vietnam Airlines'),
('VN002', '2026-04-01 12:00', '2026-04-01 14:00', 2, 3, 1, 'Vietnam Airlines'),
('VN003', '2026-04-02 09:00', '2026-04-02 11:00', 1, 3, 2, 'VietJet Air'),
('VN004', '2026-04-02 15:00', '2026-04-02 17:00', 3, 1, 2, 'Bamboo Airways');
GO

--CUSTOMERS--
INSERT INTO customers (full_name, id_number, phone, email)
VALUES
('Nguyen Van A', '100000001', '0900000001', 'a1@gmail.com'),
('Tran Van B', '100000002', '0900000002', 'b2@gmail.com'),
('Le Van C', '100000003', '0900000003', 'c3@gmail.com'),
('Pham Van D', '100000004', '0900000004', 'd4@gmail.com'),
('Hoang Van E', '100000005', '0900000005', 'e5@gmail.com'),
('Nguyen Thi F', '100000006', '0900000006', 'f6@gmail.com'),
('Tran Thi G', '100000007', '0900000007', 'g7@gmail.com'),
('Le Thi H', '100000008', '0900000008', 'h8@gmail.com'),
('Pham Thi I', '100000009', '0900000009', 'i9@gmail.com'),
('Hoang Thi K', '100000010', '0900000010', 'k10@gmail.com'),
('Do Van L', '100000011', '0900000011', 'l11@gmail.com'),
('Bui Van M', '100000012', '0900000012', 'm12@gmail.com'),
('Dang Van N', '100000013', '0900000013', 'n13@gmail.com'),
('Ngo Van O', '100000014', '0900000014', 'o14@gmail.com'),
('Vu Van P', '100000015', '0900000015', 'p15@gmail.com'),
('Do Thi Q', '100000016', '0900000016', 'q16@gmail.com'),
('Bui Thi R', '100000017', '0900000017', 'r17@gmail.com'),
('Dang Thi S', '100000018', '0900000018', 's18@gmail.com'),
('Ngo Thi T', '100000019', '0900000019', 't19@gmail.com'),
('Vu Thi U', '100000020', '0900000020', 'u20@gmail.com');
GO

--TICKETS--
INSERT INTO tickets (flight_id, customer_id, seat_id, price, tax)
VALUES
(1,1,1,1000000,100000),
(1,2,2,1000000,100000),
(1,3,3,1000000,100000),
(1,4,4,1000000,100000),
(1,5,5,1000000,100000),

(2,6,6,1200000,120000),
(2,7,7,1200000,120000),
(2,8,8,1200000,120000),
(2,9,9,1200000,120000),
(2,10,10,1200000,120000),

(3,11,51,900000,90000),
(3,12,52,900000,90000),
(3,13,53,900000,90000),
(3,14,54,900000,90000),
(3,15,55,900000,90000),

(4,16,56,1500000,150000),
(4,17,57,1500000,150000),
(4,18,58,1500000,150000),
(4,19,59,1500000,150000),
(4,20,60,1500000,150000);
GO

--PAYMENTS--
INSERT INTO payments (ticket_id, payment_method, payment_status)
VALUES
(1,'BANK_TRANSFER','SUCCESS'),
(2,'EWALLET','SUCCESS'),
(3,'LOCAL_CARD','FAILED'),
(4,'BANK_TRANSFER','SUCCESS'),
(5,'EWALLET','FAILED'),

(6,'BANK_TRANSFER','SUCCESS'),
(7,'LOCAL_CARD','SUCCESS'),
(8,'EWALLET','FAILED'),
(9,'BANK_TRANSFER','SUCCESS'),
(10,'LOCAL_CARD','SUCCESS');
GO

-- Kiểm tra ghế
SELECT * FROM seats;

-- Kiểm tra vé
SELECT * FROM tickets;

-- Kiểm tra chuyến bay
SELECT * FROM flights;