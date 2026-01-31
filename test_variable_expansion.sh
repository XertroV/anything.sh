#!/bin/bash

# Test script for variable expansion

echo "=== Basic Variable Expansion ==="
name="Alice"
echo "Hello, $name"
echo "Hello, ${name}"

echo ""
echo "=== Variable in Strings ==="
count=5
echo "There are $count apples"
echo "There are ${count} apples"

echo ""
echo "=== Undefined Variables ==="
echo "Undefined: $undefined_var"
echo "Undefined with default: ${undefined_var:-default_value}"

echo ""
echo "=== Variable Expansion in Double vs Single Quotes ==="
var="World"
echo "Double quotes: Hello $var"
echo 'Single quotes: Hello $var'

echo ""
echo "=== Command Substitution ==="
current_date=$(date +%Y-%m-%d)
echo "Today is: $current_date"

echo ""
echo "=== Arithmetic Expansion ==="
num=10
result=$((num * 2))
echo "$num * 2 = $result"

echo ""
echo "=== Array Expansion ==="
arr=(apple banana cherry)
echo "First element: ${arr[0]}"
echo "All elements: ${arr[@]}"
echo "Number of elements: ${#arr[@]}"

echo ""
echo "=== Parameter Expansion ==="
filename="document.txt"
echo "Filename: $filename"
echo "Remove extension: ${filename%.txt}"
echo "Uppercase: ${filename^^}"
echo "Length: ${#filename}"
