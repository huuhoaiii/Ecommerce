--1. Customer Behavior Analysis

--Top 10 Highest Frequency Customers and Their Purchasing Habits
WITH T1 AS -- Count the number of product orders for each customer
(
	SELECT	C.customer_unique_id, 
			n.product_category_name_english, 
			COUNT(DISTINCT i.order_id)  AS number_of_products
	FROM customers c
	JOIN orders o
		ON c.customer_id = o.customer_id
	JOIN order_items i
		ON i.order_id = o.order_id
	JOIN products p
		ON p.product_id = i.product_id
	JOIN product_category_name_translation n
		ON n.product_category_name = p.product_category_name
	GROUP BY product_category_name_english, customer_unique_id 
),
T2 AS --Count the number of order for each customer
(
	SELECT TOP 10  
			C.customer_unique_id, 
			COUNT(DISTINCT c.customer_id) as number_of_orders , 
			SUM(payment_value) as total_payment
	FROM customers c
	JOIN orders o
		ON c.customer_id = o.customer_id
	JOIN order_payments p
		ON p.order_id = o.order_id
	GROUP BY customer_unique_id
	ORDER BY 2 DESC
),
T3 AS --Rank the number of product
(
	SELECT	T2.total_payment,
			T2.customer_unique_id, 
			T1.product_category_name_english, 
			T2.number_of_orders, 
			T1.number_of_products, 
			DENSE_RANK() OVER (PARTITION BY  T2.customer_unique_id ORDER BY number_of_products DESC) AS ranks
	FROM T1 
	INNER JOIN T2
		ON T1.customer_unique_id = T2.customer_unique_id
)
SELECT	T3.customer_unique_id, 
		number_of_orders,
		product_category_name_english, 
		number_of_products, 
		total_payment
FROM T3
WHERE ranks = 1 
ORDER BY 2 DESC, 1;

--Top 10 the Cities with the highest number of customer
WITH sub AS (
    SELECT TOP 10 
			customer_city,customer_state, 
			COUNT(*) AS number_of_customer
    FROM customers
    GROUP BY customer_city, customer_state
	ORDER BY 3 DESC
),
sub2 as
(
	SELECT
		geolocation_city,
		geolocation_lat, 
		geolocation_lng,
		ROW_NUMBER() OVER (PARTITION BY geolocation_city ORDER BY (SELECT NULL)) as num
	FROM geolocation g
	JOIN sub s
		ON G.geolocation_city = S.customer_city
)
SELECT
    s.customer_city, 
	s.customer_state,
    s2.geolocation_lat, 
    s2.geolocation_lng, 
    s.number_of_customer
FROM sub s
JOIN sub2 s2
    ON s.customer_city = s2.geolocation_city
WHERE num = 1
ORDER BY 5 DESC;


--Top 10 hightest payment value
SELECT	TOP 10
		customer_unique_id, 
		SUM(payment_value) as total_payment_value,
		COUNT(*) as number_of_orders
FROM customers c
JOIN orders o
	ON c.customer_id = o.customer_id
JOIN order_payments p
	ON p.order_id = o.order_id
GROUP BY customer_unique_id
ORDER BY 2 DESC


--2.Sales Performance	
--Evaluate the effectiveness of different sales channels
WITH sub as
(
	SELECT	seller_id, 
			FORMAT((DATEDIFF(HOUR, first_contact_date,  won_date)/24.0), 'N2') as hour_successfull_contact
	FROM leads_closed l
	JOIN leads_qualified q
		ON q.mql_id = l.mql_id
)
SELECT	seller_id, 
		hour_successfull_contact, 
		RANK() OVER (ORDER BY hour_successfull_contact) as rank
FROM sub

-- The number of leads closed per montn

SELECT	DATENAME(MONTH, won_date) AS Month, 
		COUNT(*) as number_of_leads
FROM leads_closed
GROUP BY DATENAME(MONTH, won_date)
ORDER BY 2 desc

--3.Product Analysis
--Top 10 Products with the Highest Number of Orders
SELECT TOP 10	product_category_name_english as product, 
				COUNT(p.order_id) as number_of_order, 
				SUM(p.payment_value) as total_payment
FROM product_category_name_translation tr
Join products pr
	ON tr.product_category_name = pr.product_category_name
Join order_items it
	ON it.product_id = pr.product_id
Join orders o
	ON o.order_id= it.order_id
Join order_payments p
	ON p.order_id = o.order_id
GROUP BY product_category_name_english
ORDER BY 2 DESC

--Top 10 Products with the Lowest Number of Orders
SELECT TOP 10	product_category_name_english as product, 
				COUNT(p.order_id) as number_of_order, 
				SUM(p.payment_value) as total_payment
FROM product_category_name_translation tr
Join products pr
	ON tr.product_category_name = pr.product_category_name
Join order_items it
	ON it.product_id = pr.product_id
Join orders o
	ON o.order_id= it.order_id
Join order_payments p
	ON p.order_id = o.order_id
GROUP BY product_category_name_english
ORDER BY 2

--Score for each product
SELECT	product_category_name_english as product, 
		AVG(o.review_score) as avg_review_score, 
		AVG(p.payment_value) as avg_payment
FROM product_category_name_translation tr
Join products pr
	ON tr.product_category_name = pr.product_category_name
Join order_items it
	ON it.product_id = pr.product_id
Join order_reviews o
	ON o.order_id= it.order_id
Join order_payments p
	ON p.order_id = o.order_id
GROUP BY product_category_name_english
ORDER BY 2 DESC

--Top 3 Bestsellers by Business Segment for Each Month
WITH business_segment as --business segment with products
(
	SELECT DISTINCT it.product_id,
					business_segment,
					product_category_name_english
	FROM product_category_name_translation t
	JOIN products p
		ON t.product_category_name = p.product_category_name
	JOIN order_items it
		ON p.product_id = it.product_id
	JOIN sellers s
		ON s.seller_id = it.seller_id
	JOIN leads_closed l
		ON l.seller_id = s.seller_id
)
,match as
( --match product with each business segment
	SELECT	it.order_id, 
			it.product_id,
			business_segment, 
			product_category_name_english, 
			COUNT(product_category_name_english) OVER (PARTITION BY product_category_name_english, business_segment ORDER BY business_segment) countt
	FROM business_segment s
	JOIN order_items it
	ON s.product_id = it.product_id
)
,counts as --count number of each business with each Month
(
	SELECT DISTINCT DATEPART(MONTH, order_approved_at) AS Month, 
					business_segment, 
					COUNT(business_segment) OVER (PARTITION BY business_segment, DATEPART(MONTH, order_approved_at)) number_of_orders
	FROM match s
	JOIN orders o
	ON s.order_id = o.order_id
)
,ranks as -- rank number of each business with each Month
(
	SELECT	Month, 
			business_segment, 
			number_of_orders, 
			rank() OVER (PARTITION BY Month ORDER BY number_of_orders DESC) rank
	FROM counts 
)
SELECT Month, business_segment, number_of_orders
FROM ranks
WHERE rank<=3;


--4.Order Analysis
--Descriptive Statistics of Delivery Time
WITH delay_day AS
(
	SELECT	DATEDIFF(hour, order_delivered_customer_date,  
			order_estimated_delivery_date) as hour_delay
	FROM orders
)
SELECT	MAX(hour_delay) AS hightest_delay, 
		-MIN(hour_delay) AS lowest_delay,
		AVG(CASE WHEN hour_delay > 0 THEN hour_delay ELSE NULL END) AS AverageHourDelay,
		-AVG(CASE WHEN hour_delay < 0 THEN hour_delay ELSE NULL END) AS AverageHournoDelay
FROM delay_day;

-- Compare the effect of delayed delivery time on customer satisfaction
WITH delay_day AS --Create CTE time delay
(
	SELECT	order_id, 
			DATEDIFF(day, order_delivered_customer_date,  order_estimated_delivery_date) as day_delay
	FROM orders
),
avg_score_delay as 
(
	SELECT  AVG(review_score) avg_score_delay
	FROM delay_day d
	JOIN order_reviews o
		ON d.order_id = o.order_id
	WHERE day_delay<0
),
avg_score_no_delay as
(
	SELECT  AVG(review_score) avg_score_no_delay
	FROM delay_day d
	JOIN order_reviews o
		ON d.order_id = o.order_id
	WHERE day_delay>0
)
SELECT avg_score_delay,avg_score_no_delay
FROM avg_score_delay, avg_score_no_delay


--The total of each payment method 
SELECT payment_type,SUM(payment_value) as total
FROM order_payments
GROUP BY payment_type
ORDER BY 2 DESC

--Time delay with each month
WITH delay_day_2 AS
(
	SELECT	DATEDIFF(hour, order_delivered_customer_date,  
			order_estimated_delivery_date)/24.0 as Day_delay,
			DATENAME(MONTH, order_delivered_customer_date) AS Month
	FROM orders
)
SELECT	Month, 
		SUM(Day_delay) AS Total_hour
FROM delay_day_2
WHERE Month is not NULL
GROUP BY Month
ORDER BY 2 DESC

--5. Geographical Insights
--TOP 10 cities with the highest number of sales
SELECT TOP 10 seller_city, COUNT(*) as number_of_sallers
FROM sellers
GROUP BY seller_city
ORDER BY 2 DESC

--Top Cities with the Highest Number of Orders and Order Percentage
WITH sub AS (
    SELECT	customer_city, 
			COUNT(*) AS number_of_orders
    FROM customers
    GROUP BY customer_city
),
total_orders AS (
    SELECT SUM(number_of_orders) AS total
    FROM sub
)
SELECT TOP 10 
    sub.customer_city, 
    sub.number_of_orders, 
    (sub.number_of_orders * 100.0 / total_orders.total) AS order_percentage
FROM sub, total_orders
ORDER BY sub.number_of_orders DESC;




