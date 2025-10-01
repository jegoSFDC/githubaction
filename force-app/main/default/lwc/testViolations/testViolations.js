import { LightningElement, track } from 'lwc';

export default class TestViolations extends LightningElement {
    @track greeting = 'World';
    
    // Best Practice Violation: Unused variable
    unusedVariable = 'This is never used';
    
    // Best Practice Violation: Console.log in production code
    connectedCallback() {
        console.log('This should not be in production code');
        console.warn('Another console statement');
        console.error('And another one');
    }
    
    // Best Practice Violation: Function too long
    handleChange(event) {
        // This function is intentionally long to trigger PMD warnings
        const value1 = event.target.value;
        const value2 = 'some other value';
        const value3 = 'another value';
        const value4 = 'yet another value';
        const value5 = 'more values';
        const value6 = 'even more values';
        const value7 = 'still more values';
        const value8 = 'continuing with values';
        const value9 = 'almost done with values';
        const value10 = 'final value';
        
        this.greeting = value1 + value2 + value3 + value4 + value5 + 
                       value6 + value7 + value8 + value9 + value10;
        
        // More unnecessary code
        const temp1 = 'temp1';
        const temp2 = 'temp2';
        const temp3 = 'temp3';
        const temp4 = 'temp4';
        const temp5 = 'temp5';
        
        console.log('Processing: ' + temp1 + temp2 + temp3 + temp4 + temp5);
    }
    
    // Best Practice Violation: Unused method
    unusedMethod() {
        return 'This method is never called';
    }
    
    // Best Practice Violation: Too many parameters
    methodWithTooManyParameters(param1, param2, param3, param4, param5, param6, param7, param8) {
        console.log('Too many parameters: ' + param1 + param2 + param3 + param4 + param5 + param6 + param7 + param8);
    }
}
