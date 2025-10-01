import { LightningElement, track } from 'lwc';

export default class SampleComponent extends LightningElement {
    @track message = 'Hello from Sample Component!';
    @track counter = 0;

    handleClick() {
        this.counter++;
        this.message = `Button clicked ${this.counter} times!`;
    }

    handleReset() {
        this.counter = 0;
        this.message = 'Hello from Sample Component!';
    }
}
