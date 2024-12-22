#!/bin/bash

RecordFile="midecalRecord.txt"
TestFile="medicalTest"

# Arrays
declare -A TestRanges
declare -A test_units

# Load medical test data
LoadTestData() {
    CheckFile "$TestFile"
    while IFS=': ' read -r test_name range_unit; 
    do
        range=$(echo "$range_unit" | cut -d ';' -f 1 | tr ', ' ' ')
        unit=$(echo "$range_unit" | sed -n 's/.*; Unit: \([^;]*\)$/\1/p')
        test_name=$(echo "$test_name")
        TestRanges["$test_name"]="$range"
        test_units["$test_name"]="$unit"
    done < "$TestFile"
}


# Check if a file exists
CheckFile() {
    if [ ! -f "$1" ]; 
    then
        echo "Error: File '$1' Not found!"
        exit 1
    fi
}


CheckPatientId() {
    while true; do
        if [[ $1 =~ ^[0-9]{7}$ ]]; 
        then
            break
        else
            echo "  Invalid Patient ID! "
            echo "Enter Patient ID (7 digits):"
            read -r input
            set -- "$input"
        fi
    done
    PatientId="$1"  # Update the PatientId after a valid ID is entered
} 

# Check Validity of the Test Date
CheckTestDate() {
    while true; do
        if [[ $1 =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; 
        then
            break
        else
            echo "  Invalid Date!"
            echo "Enter Test Date (YYYY-MM):"
            read -r input
            set -- "$input"
        fi
    done
    TestDate="$1"  # Update the Test Date after a valid ID is entered
}

# Validate the test status
ValidateTestStatus() {
    while true; 
    do
        status=$(echo "$1" | tr '[:upper:]' '[:lower:]')  # Translate to lowercase
        case $status in
            "pending"|"completed"|"reviewed") break ;;
            *) echo "  Invalid status!"
               echo "Enter Status (Pending, Completed, Reviewed):"
               read -r input
               set -- "$input"
               ;;
        esac
    done
    status="$1"  # Update the Status after a valid ID is entered
}

# Check the validity of the result within the defined range
CheckResult() {
    TestName=$1
    Result=$2

    Range=$(echo "${TestRanges[$TestName]}" | tr ', ' ' ')
    LowRange=$(echo "$Range" | cut -d'>' -f2 | cut -d'<' -f1)
    HighRange=$(echo "$Range" | cut -d'<' -f2)

    LowRange=$(echo "$LowRange" | sed 's/[^0-9.]//g')
    HighRange=$(echo "$HighRange" | sed 's/[^0-9.]//g')
    Result=$(echo "$Result" | sed 's/[^0-9.]//g')

    if [ -z "$LowRange" ]; then
        if (( $(echo "$Result > $HighRange" | bc -l) )); 
        then
            return 1  # Upnormal
        fi
    elif [ -z "$HighRange" ]; then
        if (( $(echo "$Result < $LowRange" | bc -l) )); 
        then
            return 1  # Upnormal
        fi
    else
        if (( $(echo "$Result < $LowRange || $Result > $HighRange" | bc -l) ));
         then
            return 1  # Upnormal
        fi
    fi

    return 0  # Normal
}

# Check if the test exists in the loaded test data
CheckTestExists() {
    while true;
     do
        test_name=$(echo "$1" | tr -d ' ')
        if [[ -n "${TestRanges[$test_name]}" ]]; 
        then
            break
        else
            echo "Test name '$1' Not found."
            echo "Enter Test Name:"
            read -r input
            set -- "$input"
        fi
    done
     TestName="$1"  # Update the Test name after a valid ID is entered
}

# Check if the patient ID exists in the record file
CheckPatientExists() {
    if ! grep -q "^$1:" "$RecordFile"; 
    then
        echo "Patient Id '$1' Not found."
        exit 1
    fi
}

# Add a new record
AddRecord() {
    CheckFile "$RecordFile"
    echo "Enter Patient ID (7 digits):"
    read -r PatientId
    CheckPatientId "$PatientId"

    echo "Enter Test Name:"
    echo "  Choose One:"
    CheckFile "$TestFile"
    while IFS=': ' read -r test_name range_unit; 
    do
        echo "   $test_name"
    done < "$TestFile"
    read -r TestName
    CheckTestExists "$TestName"

    echo " "
    echo "Enter Test Date (YYYY-MM):"
    read -r TestDate
    CheckTestDate "$TestDate"

    echo " "
    echo "Enter Result:"
    read -r Result

    echo " "
    echo "Enter Status (Pending, Completed, Reviewed):"
    read -r Status
    ValidateTestStatus "$Status"

    if [ $? -eq 0 ]; 
    then
        echo "$PatientId: $TestName, $TestDate, $Result, ${test_units[$TestName]}, $Status" >> "$RecordFile"
        echo "  --Record added successfully!"

    fi
}

# Search for tests by Patient ID
SearchByPatient() {
    echo "Enter Patient ID:"
    read -r PatientId
    CheckPatientId "$PatientId"
    CheckPatientExists "$PatientId"
    echo ""
    echo "   1. Retrieve all tests"
    echo "   2. Retrieve all up normal tests"
    echo "   3. Retrieve tests in a specific period (YYYY-MM)"
    echo "   4. Retrieve tests based on status"
    echo "Choose an option:"
    read -r option

    case $option in
        1)
            grep "^$PatientId:" "$RecordFile"
            ;;
        2)
   	     grep "^$PatientId:" "$RecordFile" | while IFS=', ' read -r pid test_name test_date result unit status; 
             do
        	# Check if the test result is abnormal
        	CheckResult "$test_name" "$result"
        	if [ $? -eq 1 ]; 
        	then
           		 echo "$pid $test_name, $test_date, $result, $unit, $status"
        	fi
    	     done
	     ;;
        
        3)
            while true; do
                echo "  Enter Start date (YYYY-MM):"
                read -r FirstDate
                CheckTestDate "$FirstDate"
                echo "  Enter End date (YYYY-MM):"
                read -r LastDate
                CheckTestDate "$LastDate"

                if [[ "$LastDate" > "$FirstDate" ]]; 
                then
                    break
                else
                    echo "End date must be after Start date. Please re-enter the dates."
                fi
            done

            # Retrieve and sort records by date
            grep "^$PatientId:" "$RecordFile" | while IFS=', ' read -r pid test_name test_date result unit status; 
            do
                if [[ "$test_date" > "$FirstDate" || "$test_date" == "$FirstDate" ]] && \
                   [[ "$test_date" < "$LastDate" || "$test_date" == "$LastDate" ]]; 
                   then
                    echo "$pid $test_name, $test_date, $result $unit, $status"
                fi
            done
            ;;
        4)
            echo "Enter status to search (Pending, Completed, Reviewed):"
            read -r status
            ValidateTestStatus "$status"
            grep "^$PatientId: .* $status$" "$RecordFile"
            ;;
        *)
            echo "Invalid option!"
            ;;
    esac
}


# Search for all abnormal tests across all records and patients
SearchUpNormmmalTests() {
    while IFS=', ' read -r pid test_name test_date result unit status; 
    do
        # Check if the test result is abnormal
        CheckResult "$test_name" "$result"
        if [ $? -eq 1 ]; 
        then
            echo "$pid: $test_name, $test_date, $result, $unit, $status"
        fi
    done < "$RecordFile"
}

# Search for abnormal tests by test name
SearchUpNormalTests() {
    echo "Enter Test Name:"
    echo "  Choose One:"
    
    CheckFile "$TestFile"
    while IFS=': ' read -r TestName RangeUnit; 
    do
        echo "   $TestName"
    done < "$TestFile"
    
    read -r TestName
    CheckTestExists "$TestName"


    while IFS=', ' read -r pid test_name test_date result unit status; 
    do
        if [ "$test_name" == "$TestName" ]; 
        then
            CheckResult "$test_name" "$result"
            if [ $? -eq 1 ]; 
            then
                echo "$pid: $test_name, $test_date, $result, $unit, $status"
            fi
        fi
    done < "$RecordFile"
}


# Delete a record by Patient ID, Test Name, and Test Date
DeleteRecord() {
    # Display all records for the user 
    echo "------------------Recent Records------------------"
    cat "$RecordFile"

    echo " "
    echo "Enter Patient ID:"
    read -r PatientId
    CheckPatientId "$PatientId"
    CheckPatientExists "$PatientId"

    echo " "
    echo "Enter Test Name:"
    CheckFile "$TestFile"
    while IFS=': ' read -r test_name range_unit; 
    do
        echo "   $test_name"
    done < "$TestFile"
    read -r TestName
    CheckTestExists "$TestName"

    echo " "
    echo "Enter Test Date (YYYY-MM):"
    read -r TestDate

    # Delete the matching record
    if [ $? = 0 ]; then
        sed -i "/^$PatientId: $TestName, $TestDate,/d" "$RecordFile"
        echo " --Record deleted successfully"
    fi
}

# Update an existing test result
UpdateTestResult() {

    # Display all records for the user
    echo "All records in the system:"
    cat "$RecordFile"
    echo ""

    echo "Enter Patient ID:"
    read -r PatientId
    CheckPatientId "$PatientId"
    CheckPatientExists "$PatientId"

    echo "Enter Test Name:"
    echo "  Choose One:"
    CheckFile "$TestFile"
    while IFS=': ' read -r test_name _; 
    do
        echo "   $test_name"
    done < "$TestFile"
    
    read -r TestName
    CheckTestExists "$TestName"

    echo "Enter Test Date (format: YYYY-MM):"
    read -r TestDate

    # Check if the specific test for the patient with the given date exists in the record
    if grep -q "^$PatientId: $TestName, $TestDate," "$RecordFile"; 
    then

        echo " "
        echo "Enter New Result:"
        read -r Result

        # Escape any special characters in TestName for use in sed
        escapedTestName=$(echo "$TestName" | sed 's/[][\/.^$*]/\\&/g')

        # Update the record with the new result, preserving the unit and other fields
        sed -i "/^$PatientId: $escapedTestName, $TestDate,/s/\(, \)[^,]*\(\, [^,]*\)\(, [^,]*\)$/\1$Result\2\3/" "$RecordFile"
        
        echo " --Test result updated successfully!"
    else
        echo " --Test '$TestName' for Patient ID '$PatientId' on date '$TestDate' not found."
    fi
}


# Calculate the average test value for each test
AverageTestValue() {

    # Create an array to store the sum of each test
    declare -A SumResult

    # Get the total number of test names from the medicalTest File
    TotalTests=$(wc -l < medicalTest)

    # Iterate over each record to sum the results
    while IFS=', ' read -r pid test_name test_date result unit status; 
    do
        # Remove any non-numeric characters from the result
        numeric_result=$(echo "$result" | sed 's/[^0-9.]//g')

        # Initialize if the test_name is not already in the array
        if [ -z "${SumResult[$test_name]}" ]; then
            SumResult["$test_name"]=0
        fi

        # Add the result to the sum
        SumResult["$test_name"]=$(echo "${SumResult[$test_name]} + $numeric_result" | bc)
    done < "$RecordFile"

    # Calculate and display the average for each test
    for test_name in "${!SumResult[@]}"; do
        total_sum=${SumResult[$test_name]}
        if [ "$TotalTests" -ne 0 ]; then
            average=$(echo "scale=2; $total_sum / $TotalTests" | bc)
            echo " "
            echo " Average for $test_name: $average ${test_units[$test_name]}"
        fi
    done
}


# Main menu
LoadTestData #change to read 

while true; 
do
    echo ""
    echo "--------------Medical Record Management System--------------"
    echo ""
    echo "------Hello, Choose one:"
    echo "       1. Add New Record"
    echo "       2. Delete Record"
    echo "       3. Retrieve Records by Patient ID"
    echo "       4. Search for Upormal Tests"
    echo "       5. Average Test Value"
    echo "       6. Update an existing test result"
    echo "       7. Exit"
    read -r Choice

    case $Choice in
        1) AddRecord ;;
        2) DeleteRecord ;;
        3) SearchByPatient ;;
        4) SearchUpNormalTests ;;
        5) AverageTestValue ;;
        6) UpdateTestResult ;;
        7) exit ;;
        *) echo "Invalid Choice! Please Try again." ;;
    esac
done 
